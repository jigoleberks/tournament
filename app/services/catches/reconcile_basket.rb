module Catches
  # Re-derives an entire (entry, species) basket from scratch after a change that
  # can alter which catches qualify — most notably a judge length edit, which can
  # pull a previously-unplaced backup into the basket or drop a now-smaller fish.
  #
  # Sibling to ReconcileFreedSlot, and the two must be read together: that one
  # re-fills a SINGLE slot freed by a deactivation (Standard -> PromoteBackup),
  # this one re-derives the WHOLE basket (Standard -> ReconcileStandard). The
  # non-Standard branches are identical because BvS/Smallest Fish/Pro Walleye
  # always re-derive from the full eligible set regardless. Keeping this mapping
  # here (not inlined in ApplyJudgeAction) means adding a scoring format updates
  # the reconciliation layer in one obvious place instead of two.
  class ReconcileBasket
    def self.call(tournament:, entry:, species:)
      if tournament.format_smallest_fish?
        ReconcileSmallestFish.call(tournament: tournament, entry: entry, species: species)
      elsif tournament.format_pro_walleye?
        ReconcileProWalleye.call(tournament: tournament, entry: entry, species: species)
      elsif tournament.format_biggest_vs_smallest?
        ReconcileBvsExtremes.call(tournament: tournament, entry: entry, species: species)
      elsif tournament.format_fish_train? || tournament.format_hidden_length? || tournament.format_tagged?
        # fish_train is append-only; hidden_length/tagged keep every catch, so a
        # length edit never changes which catches are placed.
        nil
      else
        ReconcileStandard.call(tournament: tournament, entry: entry, species: species)
      end
    end
  end
end
