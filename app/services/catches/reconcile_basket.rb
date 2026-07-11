module Catches
  # Re-derives an entire (entry, species) basket from scratch after a change that
  # can alter which catches qualify — most notably a judge length edit, which can
  # pull a previously-unplaced backup into the basket or drop a now-smaller fish.
  #
  # This is the single source of the format->reconciler mapping. ReconcileFreedSlot
  # (single-slot repair after a deactivation) handles only the Standard family
  # itself (the cheaper PromoteBackup) and defers every other format to this
  # method, because BvS/Smallest Fish/Pro Walleye always re-derive from the full
  # eligible set regardless of what triggered the reconcile, and Fish Train/Hidden
  # Length/Tagged never refill a freed slot. So adding a scoring format updates the
  # reconciliation layer in exactly one place.
  class ReconcileBasket
    # exclude_catch_id: when a freed slot is being re-filled, the catch that
    # vacated it is re-placed separately (PlaceInSlots) and must be excluded from
    # the re-derive so it isn't placed twice. Nil for a plain length-edit reconcile
    # where the edited catch legitimately stays in the basket.
    def self.call(tournament:, entry:, species:, exclude_catch_id: nil)
      if tournament.format_smallest_fish?
        ReconcileSmallestFish.call(tournament: tournament, entry: entry, species: species, exclude_catch_id: exclude_catch_id)
      elsif tournament.format_pro_walleye?
        ReconcileProWalleye.call(tournament: tournament, entry: entry, species: species, exclude_catch_id: exclude_catch_id)
      elsif tournament.format_biggest_vs_smallest?
        ReconcileBvsExtremes.call(tournament: tournament, entry: entry, species: species, exclude_catch_id: exclude_catch_id)
      elsif tournament.format_progressive_length?
        ReconcileProgressiveLength.call(tournament: tournament, entry: entry, species: species, exclude_catch_id: exclude_catch_id)
      elsif tournament.format_fish_train? || tournament.format_hidden_length? || tournament.format_tagged? || tournament.format_beat_the_average?
        # fish_train is append-only; hidden_length/tagged/beat_the_average keep
        # every catch, so a length edit never changes which catches are placed
        # (beat_the_average's average is re-derived on read; a DQ deactivates
        # its placement through the normal deactivation path).
        nil
      else
        ReconcileStandard.call(tournament: tournament, entry: entry, species: species, exclude_catch_id: exclude_catch_id)
      end
    end
  end
end
