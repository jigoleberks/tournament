module Catches
  # Single source of truth for the slot-selection ordering used by BOTH the
  # incremental placement path (PlaceInSlots) and the whole-basket reconcilers
  # (SlotPlacement#by_length, ReconcileBvsExtremes). Keeping the key in one place
  # is what guarantees incremental placement and a later reconcile keep and drop
  # exactly the same catches — previously the tuple was copied into each and only
  # kept in sync by a test, which let equal-length tie shapes diverge.
  #
  # desc: true ranks largest-first; a SMALLER key sorts better. The tiebreak —
  # earliest captured_at_device, then lowest id — encodes "first-to-set wins".
  module SlotRanking
    module_function

    def key(catch_record, desc:)
      sign = desc ? -1 : 1
      [sign * catch_record.length_inches.to_f, catch_record.captured_at_device.to_i, catch_record.id]
    end
  end
end
