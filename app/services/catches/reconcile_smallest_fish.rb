module Catches
  class ReconcileSmallestFish
    # Re-derives the N smallest active placements (by current length_inches) for
    # one (entry, species) from scratch, where N is the species' scoring slot
    # count. Use after any non-incremental change to the eligible-catch set: DQ,
    # manual length/species edit, member drop. PromoteBackup assumes
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
      reconcile_top_n(desc: false) # N smallest
    end
  end
end
