module Catches
  # Shared eligibility + placement primitives for the services that re-derive a
  # tournament entry's slots from scratch (ReconcileStandard, ReconcileSmallestFish,
  # ReconcileBvsExtremes, ReconcileProWalleye) or fill a single freed slot
  # (PromoteBackup). Keeping the geofence rule and the activate-or-create upsert
  # in one place means a change to eligibility lands everywhere at once.
  #
  # Expects the including service to set @tournament, @entry, and @species.
  module SlotPlacement
    private

    # A catch counts toward a tournament only if it has no recorded location, or
    # sits inside Saskatchewan (and inside the lake when the tournament is local).
    def slot_eligible?(catch_record)
      return true if catch_record.latitude.nil?
      return false unless catch_record.in_geofence?(:sask)
      return true unless @tournament.local?
      catch_record.in_geofence?(:lake)
    end

    # The tournament's catch window as a Range for captured_at_device filters.
    def tournament_window
      @tournament.starts_at..(@tournament.ends_at || ::Time.current)
    end

    def entry_member_ids
      @entry.tournament_entry_members.pluck(:user_id)
    end

    # Non-DQ, in-window catches of @species by @entry's members that pass the
    # geofence check. A length is required to rank a catch (a NULL would sort as
    # the smallest/extreme and wrongly claim a slot), so we exclude length-less
    # rows here — defensive, since Catch validates length presence.
    def eligible_catches
      ::Catch.where(user_id: entry_member_ids,
                    species_id: @species.id,
                    captured_at_device: tournament_window)
             .where.not(status: ::Catch.statuses[:disqualified])
             .where.not(length_inches: nil)
             .select { |c| slot_eligible?(c) }
    end

    # Rank catches for slot selection by length. The tiebreak — earliest
    # captured_at_device, then lowest id — encodes "first-to-set wins", matching
    # the strict >/< no-op-on-ties semantics of the incremental PlaceInSlots
    # branches. desc: true is largest-first (Standard, Pro Walleye, BvS);
    # desc: false is smallest-first (Smallest Fish).
    def by_length(catches, desc:)
      sign = desc ? -1 : 1
      catches.sort_by { |c| [sign * c.length_inches.to_f, c.captured_at_device.to_i, c.id] }
    end

    # Whole-basket re-derive shared by ReconcileStandard (desc: true) and
    # ReconcileSmallestFish (desc: false): lock @entry, clear its current basket
    # for @species, and re-activate the N extreme catches, where N is the
    # species' scoring slot count. Use after any non-incremental change that can
    # pull an unplaced backup into the basket or drop a now-smaller fish (a judge
    # length edit, a DQ, a member drop) — PromoteBackup only fills a single freed
    # slot and misses the "a backup grew into the basket" case.
    def reconcile_top_n(desc:)
      ::ActiveRecord::Base.transaction do
        @entry.lock!  # serialize with PlaceInSlots / PromoteBackup / the reconcilers

        slot = @tournament.scoring_slots.find_by(species_id: @species.id)
        n = slot&.slot_count.to_i
        # No scoring slot for this species: nothing to re-derive against, so leave
        # any existing placements untouched rather than clearing the basket first.
        return if n.zero?

        # Deactivate before re-activating so we never collide with
        # idx_active_placements_uniq_per_slot on a row that shares the target slot.
        @entry.catch_placements
              .where(species_id: @species.id, active: true)
              .update_all(active: false)

        eligible = eligible_catches
        return if eligible.empty?

        by_length(eligible, desc: desc).first(n).each_with_index do |catch_record, slot_index|
          activate_placement!(catch_record, slot_index: slot_index)
        end
      end
    end

    # Activate the (entry, species, slot_index) placement for catch_record,
    # reactivating an existing inactive row instead of colliding with
    # idx_active_placements_uniq_per_slot. Returns the placement.
    def activate_placement!(catch_record, slot_index:)
      existing = ::CatchPlacement.find_by(
        catch_id: catch_record.id, tournament_entry_id: @entry.id,
        species_id: @species.id, slot_index: slot_index
      )
      if existing
        existing.update!(active: true)
        existing
      else
        ::CatchPlacement.create!(
          catch: catch_record, tournament: @tournament, tournament_entry: @entry,
          species: @species, slot_index: slot_index, active: true
        )
      end
    end
  end
end
