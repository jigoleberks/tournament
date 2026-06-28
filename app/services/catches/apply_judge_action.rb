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
          # Lock affected entries in id order so concurrent PlaceInSlots /
          # other judge actions don't deadlock with us.
          entry_ids = @catch.catch_placements.active.pluck(:tournament_entry_id).uniq.sort
          entry_ids.each { |id| TournamentEntry.lock.find(id) }

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
            # Lock the union of (entries currently holding placements for this
            # catch) and (entries the inner PlaceInSlots will iterate at
            # @catch.captured_at_device), in id-asc order. Locking only the
            # first set would let PlaceInSlots later acquire an intermediate
            # entry id while a concurrent PlaceInSlots in another transaction
            # holds it and waits for one of ours — a deadlock.
            current_entry_ids = @catch.catch_placements.active.pluck(:tournament_entry_id)
            reachable_entry_ids = ::Tournaments::ActiveForUser
              .with_entries(user: @catch.user, at: @catch.captured_at_device)
              .map { |row| row[:entry].id }
            (current_entry_ids + reachable_entry_ids).uniq.sort.each do |id|
              TournamentEntry.lock.find(id)
            end

            freed = @catch.catch_placements.active.to_a
            @catch.catch_placements.active.update_all(active: false)
            @catch.update!(species_id: @species_id)
            freed.each { |p| Catches::ReconcileFreedSlot.call(placement: p) }

            # Re-place the catch under the new species. PlaceInSlots will only
            # place in tournaments where the user has an entry at captured_at_device
            # AND there's a scoring slot for the new species; otherwise the catch
            # stays unplaced.
            # broadcast: false — we're inside ApplyJudgeAction's outer transaction.
            # The caller's post-transaction broadcast at the bottom of #call covers
            # any newly-affected tournaments. Broadcasting here would expose
            # pre-commit state to subscribers via separate DB connections.
            Catches::PlaceInSlots.call(catch: @catch, broadcast: false)
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
          @catch.update!(status: :needs_review)
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
          # Lock entries PlaceInSlots will iterate (in id order) before re-placing.
          ::Tournaments::ActiveForUser
            .with_entries(user: @catch.user, at: @catch.captured_at_device)
            .map { |row| row[:entry].id }.uniq.sort
            .each { |id| TournamentEntry.lock.find(id) }
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

      if @notify_owner && @judge.id != @catch.user_id
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
    # ComputeFlags only owns the location/time/duplicate flags; imported_photo is
    # set out-of-band by FlagImportedPhotoJob and would be silently wiped by a
    # full overwrite, so carry it across the recompute.
    def recompute_flags!
      recomputed = ::Catches::ComputeFlags.call(@catch)
      recomputed << "imported_photo" if @catch.flags.include?("imported_photo")
      @catch.update!(flags: recomputed)
    end

    # Drop the catch's active placements, promote backups into the freed slots,
    # then re-place the catch under its current state. Mirrors the species-change
    # path: a changed location or override can make the catch newly (in)eligible,
    # so we must rebuild placements from scratch. Locks the union of entries the
    # catch currently occupies and entries PlaceInSlots will iterate, in id order,
    # to avoid deadlocks with concurrent placement.
    def deactivate_and_replace!
      current_entry_ids = @catch.catch_placements.active.pluck(:tournament_entry_id)
      reachable_entry_ids = ::Tournaments::ActiveForUser
        .with_entries(user: @catch.user, at: @catch.captured_at_device)
        .map { |row| row[:entry].id }
      (current_entry_ids + reachable_entry_ids).uniq.sort.each { |id| TournamentEntry.lock.find(id) }

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
