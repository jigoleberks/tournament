module Catches
  class ReconcileSmallestFish
    # Re-derives the N smallest active placements (by current length_inches) for
    # one (entry, species) from scratch, where N is the species' scoring slot
    # count. Use after any non-incremental change to the eligible-catch set: DQ,
    # manual length/species edit, member drop. PromoteBackup/RebalanceSlots assume
    # "promote the largest" semantics, which is wrong for Smallest Fish — we
    # re-pick the N smallest from the whole eligible set instead.
    include SlotPlacement

    def self.call(tournament:, entry:, species:)
      new(tournament: tournament, entry: entry, species: species).call
    end

    def initialize(tournament:, entry:, species:)
      @tournament, @entry, @species = tournament, entry, species
    end

    def call
      ActiveRecord::Base.transaction do
        @entry.lock!  # serialize with PlaceInSlots / PromoteBackup / RebalanceSlots

        slot = @tournament.scoring_slots.find_by(species_id: @species.id)
        n = slot&.slot_count.to_i

        # Deactivate first so we never collide with idx_active_placements_uniq_per_slot
        # when re-activating an inactive row that shares the target slot.
        @entry.catch_placements
              .where(species_id: @species.id, active: true)
              .update_all(active: false)

        return if n.zero?

        eligible = eligible_catches
        return if eligible.empty?

        # N smallest by length; ties broken by earliest captured_at_device then
        # lowest id — matches the "first-to-set wins" semantics of the incremental
        # PlaceInSlots smallest_fish branch (strict < no-ops on ties).
        smallest = eligible
          .sort_by { |c| [c.length_inches.to_f, c.captured_at_device.to_i, c.id] }
          .first(n)

        smallest.each_with_index do |catch_record, slot_index|
          activate_placement!(catch_record, slot_index: slot_index)
        end
      end
    end
  end
end
