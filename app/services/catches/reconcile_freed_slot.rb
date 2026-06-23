module Catches
  # Re-fills the slot(s) freed when a placement is deactivated — by a DQ, a
  # manual species change, or a dropped member. The right strategy depends on
  # the tournament format; this ladder is the single source of that mapping so
  # the call sites (ApplyJudgeAction, DropMemberFromEntry) can't drift apart.
  class ReconcileFreedSlot
    def self.call(placement:)
      tournament = placement.tournament
      entry      = placement.tournament_entry
      species    = placement.species

      # PromoteBackup picks the largest non-placed catch — correct for Standard
      # but wrong for BvS/Smallest Fish (which re-derive their extremes from the
      # whole eligible set) and for Fish Train (append-only, never refilled).
      if tournament.format_biggest_vs_smallest?
        ReconcileBvsExtremes.call(tournament: tournament, entry: entry, species: species)
      elsif tournament.format_smallest_fish?
        ReconcileSmallestFish.call(tournament: tournament, entry: entry, species: species)
      elsif tournament.format_fish_train?
        # Fish Train is append-only: a freed car stays a permanent hole. The
        # angler recovers by catching forward, not by promoting a backup.
        nil
      else
        PromoteBackup.call(freed_placement: placement)
      end
    end
  end
end
