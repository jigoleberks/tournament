module Catches
  class ReconcileBvsExtremes
    # Re-derives the BvS active placements (biggest + smallest by current
    # length_inches) for one (entry, species) from scratch. Use after any
    # non-incremental change to the eligible-catch set: DQ, manual length/species
    # edit, member drop. PromoteBackup/RebalanceSlots assume "promote the
    # largest" semantics, which is wrong when the freed slot was holding the
    # smaller extreme — for BvS we have to look at the whole catch set.
    def self.call(tournament:, entry:, species:)
      new(tournament: tournament, entry: entry, species: species).call
    end

    def initialize(tournament:, entry:, species:)
      @tournament, @entry, @species = tournament, entry, species
    end

    def call
      ActiveRecord::Base.transaction do
        @entry.lock!  # serialize with PlaceInSlots / PromoteBackup / RebalanceSlots

        # Deactivate first so we never collide with idx_active_placements_uniq_per_slot
        # when re-activating an inactive row that shares the target slot.
        @entry.catch_placements
              .where(species_id: @species.id, active: true)
              .update_all(active: false)

        eligible = eligible_catches
        return if eligible.empty?

        # Tiebreaker for same-length catches: earliest captured_at_device wins,
        # then lowest id. Matches the "first-to-set wins" semantics of the
        # incremental PlaceInSlots BvS branch (which no-ops on ties).
        biggest  = eligible.min_by { |c| [-c.length_inches.to_f, c.captured_at_device.to_i, c.id] }
        remaining = eligible - [biggest]
        if remaining.empty?
          place!(biggest, slot_index: 0)
        else
          smallest = remaining.min_by { |c| [c.length_inches.to_f, c.captured_at_device.to_i, c.id] }
          place!(biggest, slot_index: 0)
          place!(smallest, slot_index: 1)
        end
      end
    end

    private

    def place!(catch_record, slot_index:)
      existing = ::CatchPlacement.find_by(
        catch_id: catch_record.id, tournament_entry_id: @entry.id,
        species_id: @species.id, slot_index: slot_index
      )
      if existing
        existing.update!(active: true)
      else
        ::CatchPlacement.create!(
          catch: catch_record, tournament: @tournament, tournament_entry: @entry,
          species: @species, slot_index: slot_index, active: true
        )
      end
    end

    def eligible_catches
      window = (@tournament.starts_at..(@tournament.ends_at || Time.current))
      member_ids = @entry.tournament_entry_members.pluck(:user_id)
      ::Catch.where(user_id: member_ids,
                    species_id: @species.id,
                    captured_at_device: window)
             .where.not(status: ::Catch.statuses[:disqualified])
             .select { |c| eligible?(c) }
    end

    def eligible?(c)
      return true if c.latitude.nil?
      return false unless ::Geofence.includes?(:sask, c.latitude, c.longitude)
      return true unless @tournament.local?
      ::Geofence.includes?(:lake, c.latitude, c.longitude)
    end
  end
end
