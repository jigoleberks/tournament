module Catches
  class ReconcileBvsExtremes
    # Re-derives the BvS active placements (biggest + smallest by current
    # length_inches) for one (entry, species) from scratch. Use after any
    # non-incremental change to the eligible-catch set: DQ, manual length/species
    # edit, member drop. PromoteBackup assumes "promote the
    # largest" semantics, which is wrong when the freed slot was holding the
    # smaller extreme — for BvS we have to look at the whole catch set.
    include SlotPlacement

    def self.call(tournament:, entry:, species:)
      new(tournament: tournament, entry: entry, species: species).call
    end

    def initialize(tournament:, entry:, species:)
      @tournament, @entry, @species = tournament, entry, species
    end

    def call
      ActiveRecord::Base.transaction do
        @entry.lock!  # serialize with PlaceInSlots / PromoteBackup / ReconcileStandard

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
          activate_placement!(biggest, slot_index: 0)
        else
          smallest = remaining.min_by { |c| [c.length_inches.to_f, c.captured_at_device.to_i, c.id] }
          activate_placement!(biggest, slot_index: 0)
          activate_placement!(smallest, slot_index: 1)
        end
      end
    end
  end
end
