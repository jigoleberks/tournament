module Catches
  class PromoteBackup
    def self.call(freed_placement:)
      new(freed_placement: freed_placement).call
    end

    def initialize(freed_placement:)
      @placement  = freed_placement
      @tournament = freed_placement.tournament
      @entry      = freed_placement.tournament_entry
      @species    = freed_placement.species
      @slot_index = freed_placement.slot_index
    end

    def call
      ActiveRecord::Base.transaction do
        @entry.lock!  # serialize with PlaceInSlots / RebalanceSlots on the same entry

        candidate = find_candidate
        return nil if candidate.nil?
        existing = ::CatchPlacement.find_by(
          catch_id: candidate.id, tournament_entry_id: @entry.id,
          species_id: @species.id, slot_index: @slot_index
        )
        if existing
          existing.update!(active: true)
          existing
        else
          ::CatchPlacement.create!(
            catch: candidate, tournament: @tournament, tournament_entry: @entry,
            species: @species, slot_index: @slot_index, active: true
          )
        end
      end
    end

    private

    def find_candidate
      window = (@tournament.starts_at..(@tournament.ends_at || Time.current))
      member_ids = @entry.tournament_entry_members.pluck(:user_id)
      placed_ids = @entry.catch_placements
                          .where(species_id: @species.id, active: true)
                          .pluck(:catch_id)
      excluded_ids = (placed_ids + [ @placement.catch_id ]).uniq
      scope = ::Catch.where(user_id: member_ids,
                            species_id: @species.id,
                            captured_at_device: window)
                     .where.not(status: ::Catch.statuses[:disqualified])
                     .where.not(id: excluded_ids)
                     .order(length_inches: :desc, captured_at_device: :asc)
      scope.detect { |c| eligible?(c) }
    end

    def eligible?(catch_record)
      return true if catch_record.latitude.nil?
      return false unless ::Geofence.includes?(:sask, catch_record.latitude, catch_record.longitude)
      return true unless @tournament.local?
      ::Geofence.includes?(:lake, catch_record.latitude, catch_record.longitude)
    end
  end
end
