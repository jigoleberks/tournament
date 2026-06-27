module Catches
  # Shared eligibility + placement primitives for the services that re-derive a
  # tournament entry's slots from scratch (ReconcileSmallestFish,
  # ReconcileBvsExtremes) or fill a single freed slot (PromoteBackup,
  # RebalanceSlots). Keeping the geofence rule and the activate-or-create upsert
  # in one place means a change to eligibility lands everywhere at once.
  #
  # Expects the including service to set @tournament, @entry, and @species.
  module SlotPlacement
    private

    # A catch counts toward a tournament only if it has no recorded location, or
    # sits inside Saskatchewan (and inside the lake when the tournament is local).
    def slot_eligible?(catch_record)
      return true if catch_record.latitude.nil?
      return false unless catch_record.override_in_sask? || ::Geofence.includes?(:sask, catch_record.latitude, catch_record.longitude)
      return true unless @tournament.local?
      return true if catch_record.override_in_lake?
      ::Geofence.includes?(:lake, catch_record.latitude, catch_record.longitude)
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
