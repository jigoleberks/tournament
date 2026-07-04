module Catches
  # Re-fills the slot(s) freed when a placement is deactivated — by a DQ, a
  # manual species change, or a dropped member. The right strategy depends on
  # the tournament format; this ladder is the single source of that mapping so
  # the call sites (ApplyJudgeAction, DropMemberFromEntry) can't drift apart.
  class ReconcileFreedSlot
    def self.call(placement:)
      tournament = placement.tournament

      # Standard and Big Fish Season are top-N by length: a freed slot only needs
      # its single best backup promoted, which is cheaper than re-deriving the
      # whole basket. PromoteBackup picks the largest non-placed catch — correct
      # for those, wrong for every other format. All the others either re-derive
      # from the full eligible set (BvS / Smallest Fish / Pro Walleye) or never
      # refill a freed slot (Fish Train, append-only; Hidden Length / Tagged,
      # which place every catch so there is no backup to promote). ReconcileBasket
      # already owns that format->reconciler mapping, so defer to it as the single
      # source of truth rather than duplicating the ladder here.
      if tournament.format_standard? || tournament.format_big_fish_season?
        PromoteBackup.call(freed_placement: placement)
      else
        ReconcileBasket.call(
          tournament: tournament,
          entry: placement.tournament_entry,
          species: placement.species
        )
      end
    end
  end
end
