module Catches
  class RebalanceSlots
    def self.call(tournament:, entry:, species:)
      new(tournament: tournament, entry: entry, species: species).call
    end

    def initialize(tournament:, entry:, species:)
      @tournament = tournament
      @entry = entry
      @species = species
    end

    def call
      # Each swap! is two writes (deactivate the old placement, then activate
      # or create the candidate's). Wrap so a mid-swap failure rolls back to
      # a consistent state. Rails flattens to a savepoint when the caller
      # (e.g. ApplyJudgeAction) already has an outer transaction open.
      ActiveRecord::Base.transaction do
        loop do
          smallest = smallest_active_placement
          break if smallest.nil?

          candidate = find_candidate
          break if candidate.nil?
          break if candidate.length_inches.to_f <= smallest.catch.length_inches.to_f

          swap!(smallest, candidate)
        end
      end
    end

    private

    def smallest_active_placement
      @entry.catch_placements
            .where(species_id: @species.id, active: true)
            .includes(:catch)
            .min_by { |p| p.catch.length_inches.to_f }
    end

    def find_candidate
      window = (@tournament.starts_at..(@tournament.ends_at || Time.current))
      member_ids = @entry.tournament_entry_members.pluck(:user_id)
      placed_ids = @entry.catch_placements
                         .where(species_id: @species.id, active: true)
                         .pluck(:catch_id)
      scope = ::Catch.where(user_id: member_ids,
                            species_id: @species.id,
                            captured_at_device: window)
                     .where.not(status: ::Catch.statuses[:disqualified])
                     .where.not(id: placed_ids)
                     .order(length_inches: :desc, captured_at_device: :asc)
      scope.detect { |c| eligible?(c) }
    end

    def eligible?(catch_record)
      return true if catch_record.latitude.nil?
      return false unless ::Geofence.includes?(:sask, catch_record.latitude, catch_record.longitude)
      return true unless @tournament.local?
      ::Geofence.includes?(:lake, catch_record.latitude, catch_record.longitude)
    end

    def swap!(placement, candidate)
      placement.update!(active: false)
      existing = ::CatchPlacement.find_by(
        catch_id: candidate.id, tournament_entry_id: @entry.id,
        species_id: @species.id, slot_index: placement.slot_index
      )
      if existing
        existing.update!(active: true)
      else
        ::CatchPlacement.create!(
          catch: candidate, tournament: @tournament, tournament_entry: @entry,
          species: @species, slot_index: placement.slot_index, active: true
        )
      end
    end
  end
end
