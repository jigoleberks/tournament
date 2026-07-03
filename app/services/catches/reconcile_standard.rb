module Catches
  class ReconcileStandard
    # Re-derives the N largest active placements (by current length_inches) for one
    # (entry, species) from scratch, where N is the species' scoring slot count.
    # Standard (and Big Fish Season, which shares Standard placement) keep the N
    # largest. Use after any non-incremental change that can pull a previously
    # unplaced backup into the basket or drop a now-smaller fish — e.g. a judge
    # length edit. PromoteBackup repairs only a single freed slot, so it misses the "an unplaced backup grew into the basket"
    # case; re-picking the N largest from the whole eligible set handles it.
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

        # N largest by length; ties broken by earliest captured_at_device then
        # lowest id — matches the "first-to-set wins" semantics of the incremental
        # PlaceInSlots Standard branch (strict > no-ops on ties).
        largest = eligible
          .sort_by { |c| [-c.length_inches.to_f, c.captured_at_device.to_i, c.id] }
          .first(n)

        largest.each_with_index do |catch_record, slot_index|
          activate_placement!(catch_record, slot_index: slot_index)
        end
      end
    end
  end
end
