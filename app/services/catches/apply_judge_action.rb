module Catches
  class ApplyJudgeAction
    class SelfApprovalError < StandardError; end
    class DisqualifyNoteRequired < StandardError; end

    def self.call(tournament:, catch:, judge:, action:, note: nil,
                  length_inches: nil, length_unit: nil, species_id: nil, slot_index: nil, entry_id: nil,
                  photo: nil, override_in_lake: nil, override_in_sask: nil, latitude: nil, longitude: nil)
      new(tournament: tournament, catch: catch, judge: judge, action: action, note: note,
          length_inches: length_inches, length_unit: length_unit, species_id: species_id,
          slot_index: slot_index, entry_id: entry_id, photo: photo,
          override_in_lake: override_in_lake, override_in_sask: override_in_sask,
          latitude: latitude, longitude: longitude).call
    end

    def initialize(tournament:, catch:, judge:, action:, note:, length_inches:, length_unit:, species_id:, slot_index:, entry_id:, photo:, override_in_lake:, override_in_sask:, latitude:, longitude:)
      @tournament, @catch, @judge, @action, @note = tournament, catch, judge, action.to_sym, note
      @length_inches, @length_unit = length_inches, length_unit
      @species_id, @slot_index, @entry_id = species_id, slot_index, entry_id
      @photo = photo
      @override_in_lake, @override_in_sask = override_in_lake, override_in_sask
      @latitude, @longitude = latitude, longitude
      @snapshot_old_attachment_id = nil
      @notify_owner = false
    end

    def call
      raise SelfApprovalError if @action == :approve && @judge.id == @catch.user_id
      raise DisqualifyNoteRequired if @action == :disqualify && @note.to_s.strip.empty?

      affected_tournaments = []

      ActiveRecord::Base.transaction do
        @catch.lock!  # serialize with PlaceInSlots on the same catch
        before = snapshot
        case @action
        when :approve, :dock_verify
          @catch.update!(status: :synced)
        when :flag
          @catch.update!(status: :needs_review)
        when :disqualify
          lock_entries!(@catch.catch_placements.active.pluck(:tournament_entry_id))
          freed = @catch.catch_placements.active.to_a
          @catch.catch_placements.active.update_all(active: false)
          @catch.update!(status: :disqualified)
          @notify_owner = true
          # No p.reload: the reconcile services re-query placements from the DB
          # (which already reflects the update_all above) and never read p.active.
          freed.each { |p| Catches::ReconcileFreedSlot.call(placement: p) }
        when :manual_override
          prior_length  = @catch.length_inches
          prior_species = @catch.species_id

          # Order: length first, then species, then slot-force / length-shrink rebalance.
          # Length must update before the species-change block so PlaceInSlots ranks the
          # catch with its NEW length when looking for slots in the new species.
          length_changed = @length_inches && @length_inches.to_f != prior_length.to_f
          unit_changed   = @length_unit.present? && @length_unit != @catch.length_unit
          if @length_inches && (length_changed || unit_changed)
            @catch.update!({ length_inches: @length_inches, length_unit: @length_unit }.compact)
            @notify_owner = true
          end

          if @species_id && @species_id != prior_species
            @notify_owner = true
            # Update species first, then rebuild placements from scratch so
            # PlaceInSlots ranks/places the catch under the NEW species. The
            # lock set (current + reachable entries) is independent of species,
            # so computing it inside deactivate_and_replace! after the update is
            # equivalent — and PlaceInSlots only places where the user has an
            # entry at captured_at_device and a slot exists for the new species.
            @catch.update!(species_id: @species_id)
            deactivate_and_replace!
          end

          if @slot_index && @entry_id
            @notify_owner = true
            entry = @tournament.tournament_entries.find(@entry_id)
            entry.lock!
            entry.catch_placements
              .where(species: @catch.species, slot_index: @slot_index, active: true)
              .update_all(active: false)
            CatchPlacement.create!(
              catch: @catch, tournament: @tournament, tournament_entry: entry,
              species: @catch.species, slot_index: @slot_index, active: true
            )
          elsif @length_inches && prior_length && @length_inches.to_f != prior_length.to_f
            shrank = @length_inches.to_f < prior_length.to_f
            @catch.catch_placements.active.includes(:tournament, :tournament_entry).order(:tournament_entry_id).each do |p|
              if p.tournament.format_smallest_fish?
                Catches::ReconcileSmallestFish.call(tournament: p.tournament, entry: p.tournament_entry, species: @catch.species)
              elsif p.tournament.format_fish_train?
                next
              elsif shrank && p.tournament.format_biggest_vs_smallest?
                Catches::ReconcileBvsExtremes.call(tournament: p.tournament, entry: p.tournament_entry, species: @catch.species)
              elsif shrank
                Catches::RebalanceSlots.call(tournament: p.tournament, entry: p.tournament_entry, species: @catch.species)
              end
            end
          end
        when :add_reference_photo
          old_ref_id = @catch.reference_photo.attached? ? @catch.reference_photo.blob.id : nil
          @catch.reference_photo.attach(@photo)
          # A reference photo is just a clearer image for review; it must not
          # silently reopen a disqualified catch. A DQ'd catch has no active
          # placements and can only return to scoring via :reinstate (which
          # refuses anything that isn't currently disqualified) — flipping it to
          # needs_review here would strand it: off the leaderboard, un-reinstatable.
          # Leave a disqualified catch disqualified; for any other status, queue
          # it for a judge to re-review with the new photo. update! runs either
          # way so the reference_photo validation still rejects a bad upload.
          new_status = @catch.disqualified? ? @catch.status : :needs_review
          @catch.update!(status: new_status)
          set_ivars_for_snapshot(old_ref_id: old_ref_id)
        when :geofence_override
          @catch.update!(override_in_lake: @override_in_lake, override_in_sask: @override_in_sask)
          recompute_flags!
          deactivate_and_replace!
        when :correct_location
          @catch.update!(latitude: @latitude, longitude: @longitude)
          recompute_flags!
          deactivate_and_replace!
        when :reinstate
          prior_dq = ::JudgeAction.where(catch_id: @catch.id, action: ::JudgeAction.actions[:disqualify])
                                  .order(:created_at).last
          restored_status = prior_dq&.before_state&.dig("status") || "synced"
          # A DQ'd catch has no active placements to free; just lock the entries
          # PlaceInSlots will iterate before re-placing.
          lock_entries!(reachable_entry_ids)
          @catch.update!(status: restored_status)
          @notify_owner = true
          ::Catches::PlaceInSlots.call(catch: @catch, broadcast: false)
        end
        after = snapshot

        JudgeAction.create!(
          judge_user: @judge, catch: @catch, action: @action, note: @note,
          before_state: before, after_state: after
        )

        affected_tournaments = @catch.catch_placements.includes(:tournament).map(&:tournament).uniq
      end

      # Broadcast AFTER the transaction commits so other DB connections see the
      # new state when they rebuild the leaderboard.
      affected_tournaments.each do |t|
        Placements::BroadcastLeaderboard.call(tournament: t)
      end

      # @notify_owner is only set by tournament-scoped actions (disqualify,
      # manual_override, reinstate); the guard keeps the @tournament derefs below
      # safe even though add_reference_photo intentionally passes tournament: nil.
      if @notify_owner && @tournament && @judge.id != @catch.user_id
        DeliverPushNotificationJob.perform_later(
          user_id: @catch.user_id,
          title: @tournament.name,
          body: notification_body,
          url: "/tournaments/#{@tournament.id}",
          tournament_id: @tournament.id
        )
      end
    end

    private

    def notification_body
      species_name = @catch.species&.name
      case @action
      when :disqualify      then "A judge disqualified your #{species_name} catch."
      when :manual_override then "A judge adjusted your #{species_name} catch."
      when :reinstate       then "A judge reinstated your #{species_name} catch."
      end
    end

    def set_ivars_for_snapshot(old_ref_id:)
      @snapshot_old_attachment_id = old_ref_id
    end

    # Re-derive the persisted flags column after a location/override change.
    # ComputeFlags.recompute preserves out-of-band flags (e.g. imported_photo)
    # it doesn't own, so we never have to maintain a carry-over list here.
    def recompute_flags!
      @catch.update!(flags: ::Catches::ComputeFlags.recompute(@catch))
    end

    # Lock the given entry ids in ascending order. Consistent ordering keeps
    # concurrent PlaceInSlots / other judge actions from deadlocking with us.
    def lock_entries!(entry_ids)
      entry_ids.uniq.sort.each { |id| TournamentEntry.lock.find(id) }
    end

    # Entries PlaceInSlots will iterate when re-placing this catch at its
    # captured_at_device — must be locked alongside the entries it currently
    # occupies, or a concurrent PlaceInSlots could grab an intermediate id we
    # later need while holding one we're waiting on.
    def reachable_entry_ids
      ::Tournaments::ActiveForUser
        .with_entries(user: @catch.user, at: @catch.captured_at_device)
        .map { |row| row[:entry].id }
    end

    # Drop the catch's active placements, promote backups into the freed slots,
    # then re-place the catch under its current state. A changed location,
    # override, or species can make the catch newly (in)eligible, so placements
    # are rebuilt from scratch. Used by geofence_override, correct_location, and
    # the species-change branch of manual_override.
    def deactivate_and_replace!
      lock_entries!(@catch.catch_placements.active.pluck(:tournament_entry_id) + reachable_entry_ids)
      freed = @catch.catch_placements.active.to_a
      @catch.catch_placements.active.update_all(active: false)
      freed.each { |p| ::Catches::ReconcileFreedSlot.call(placement: p) }
      ::Catches::PlaceInSlots.call(catch: @catch, broadcast: false)
    end

    def snapshot
      # Use the loaded association rather than a fresh find_by: snapshot runs for
      # both before/after states, and Rails resets @catch.species when species_id
      # changes, so this still reflects the right species on each side of an edit.
      {
        "status"            => @catch.status,
        "length_inches"     => @catch.length_inches.to_s,
        "length_unit"       => @catch.length_unit,
        "species_id"        => @catch.species_id,
        "species_name"      => @catch.species&.name,
        "active_placements" => @catch.catch_placements.where(active: true).pluck(:tournament_entry_id, :slot_index),
        "photo_attached"    => @catch.photo.attached?,
        "reference_photo_attached" => @catch.reference_photo.attached?,
        "reference_photo_blob_id" => @catch.reference_photo.attached? ? @catch.reference_photo.blob.id : nil,
        "reference_photo_prev_blob_id" => @snapshot_old_attachment_id,
        "latitude"          => @catch.latitude&.to_s,
        "longitude"         => @catch.longitude&.to_s,
        "override_in_lake"  => @catch.override_in_lake,
        "override_in_sask"  => @catch.override_in_sask,
      }
    end
  end
end
