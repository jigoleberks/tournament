class Api::CatchesController < Api::BaseController
  def create
    uuid = params.dig(:catch, :client_uuid)
    existing = idempotent_existing(uuid)
    if existing
      return render(json: serialize_existing(existing), status: :ok)
    end

    # The offline queue stamps who was signed in at capture. If a different
    # account is signed in at drain time (shared family phone), refuse rather
    # than credit the wrong angler on a live leaderboard. The record stays on
    # the device for the right user to sync later. Dedup runs first: a catch
    # the server already owns is answered normally regardless.
    queued_by = params.dig(:catch, :queued_by_user_id)
    if queued_by.present? && queued_by.to_s != current_user.id.to_s
      return render json: { errors: ["This catch was logged under a different account. Sign in as that member and retry from Pending catches."] },
                    status: :unprocessable_entity
    end

    teammate_id = params[:teammate_user_id].presence
    if teammate_id && current_club.nil?
      return render json: { errors: ["You have no active club membership."] }, status: :unprocessable_entity
    end
    teammate = teammate_id ? current_club.members.find_by(id: teammate_id) : nil
    if teammate_id && teammate.nil?
      return render json: { errors: ["Teammate not found"] }, status: :unprocessable_entity
    end

    angler = teammate || current_user
    catch_record = angler.catches.build(catch_params)
    catch_record.logged_by_user_id = current_user.id if teammate

    if teammate && !shares_entry_at?(teammate, catch_record.captured_at_device)
      return render json: { errors: ["You and this teammate aren't on the same entry in any active tournament."] }, status: :unprocessable_entity
    end

    catch_record.flags  = Catches::ComputeFlags.call(catch_record)
    # "Mark video failed and submit anyway" — an explicit angler declaration,
    # not derivable from state, so it's an external flag (survives recompute).
    if ActiveModel::Type::Boolean.new.cast(params.dig(:catch, :video_failed))
      catch_record.flags |= ["video_failed"]
    end
    catch_record.lake   = Catches::DetectLake.call(catch_record)
    catch_record.status = catch_record.flags.empty? ? :synced : :needs_review
    catch_record.synced_at = Time.current

    begin
      saved = catch_record.save
    rescue ActiveRecord::RecordNotUnique
      # Parallel retry from a flaky-LTE client raced past the find_by above.
      # The unique index on client_uuid prevented the duplicate; return the winner.
      existing = idempotent_existing(uuid)
      return render(json: serialize_existing(existing), status: :ok) if existing
      raise
    end

    if saved && catch_record.photo.attached?
      placements = Catches::PlaceInSlots.call(catch: catch_record)
      Catches::FlagDuplicates.call(catch: catch_record) if catch_record.flags.include?("possible_duplicate")
      FetchCatchConditionsJob.perform_later(catch_id: catch_record.id)
      FlagImportedPhotoJob.perform_later(catch_id: catch_record.id)
      # Stamped LAST: a crash anywhere above leaves it nil, so the dedup retry
      # knows to re-run the pipeline (see serialize_existing).
      catch_record.update_column(:placements_evaluated_at, Time.current)
      render json: serialize(catch_record, placements: placements[:created], flags: catch_record.flags), status: :created
    else
      catch_record.errors.add(:photo, "is required") unless catch_record.photo.attached?
      render json: { errors: catch_record.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  # A device retries the same client_uuid; the row may belong to either the
  # current user (their own catch) or a teammate they logged for.
  def idempotent_existing(uuid)
    return nil if uuid.blank?
    Catch.where(client_uuid: uuid)
      .where("user_id = :id OR logged_by_user_id = :id", id: current_user.id)
      .first
  end

  # The save at line ~29 commits OUTSIDE PlaceInSlots' transaction, so a 500
  # between them (deadlock on a busy night) leaves a committed catch with no
  # placements. The client's retry lands here — if we answered "ok" without
  # placing, the queued row would be deleted and the fish silently never
  # scores. Re-run placement when the pipeline never completed: PlaceInSlots
  # yields the exact same placements a first run would, and the
  # flag/condition jobs are idempotent (add_flag! is a guarded single
  # UPDATE). "No placements" alone can't be the signal — bingo keeps none by
  # design and a catch can legitimately match no slot, and re-running for
  # those on every flaky-LTE retry meant endless rebroadcast/job churn —
  # hence the placements_evaluated_at stamp, written only after a completed
  # run.
  def serialize_existing(existing)
    if existing.photo.attached? && existing.placements_evaluated_at.nil? && existing.catch_placements.none?
      placements = Catches::PlaceInSlots.call(catch: existing)
      Catches::FlagDuplicates.call(catch: existing) if existing.flags.include?("possible_duplicate")
      FetchCatchConditionsJob.perform_later(catch_id: existing.id)
      FlagImportedPhotoJob.perform_later(catch_id: existing.id)
      existing.update_column(:placements_evaluated_at, Time.current)
      serialize(existing, placements: placements[:created], flags: existing.flags)
    else
      serialize(existing, flags: existing.flags)
    end
  end

  def shares_entry_at?(teammate, at)
    Tournaments::SharedEntryAt.call(
      user_a: current_user, user_b: teammate, club: current_club, at: at || Time.current
    ).present?
  end

  def catch_params
    params.require(:catch).permit(
      :species_id, :length_inches, :length_unit, :captured_at_device, :captured_at_gps,
      :latitude, :longitude, :gps_accuracy_m, :app_build, :client_uuid, :photo, :video, :note,
      :tag_number, :weight_text
    )
  end

  def serialize(catch_record, placements: nil, flags: [])
    {
      id: catch_record.id,
      client_uuid: catch_record.client_uuid,
      status: catch_record.status,
      flags: flags,
      placements: (placements || catch_record.catch_placements).map { |p|
        { tournament_id: p.tournament_id, entry_id: p.tournament_entry_id, slot_index: p.slot_index, active: p.active }
      }
    }
  end
end
