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
      reconcile_top_n(desc: true) # N largest
    end
  end
end
