class Api::CatchesController < Api::BaseController
  def create
    uuid = params.dig(:catch, :client_uuid)
    existing = idempotent_existing(uuid)
    if existing
      return render(json: serialize(existing), status: :ok)
    end

    teammate_id = params[:teammate_user_id].presence
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

    catch_record.flags = Catches::ComputeFlags.call(catch_record)
    catch_record.status = catch_record.flags.empty? ? :synced : :needs_review
    catch_record.synced_at = Time.current

    begin
      saved = catch_record.save
    rescue ActiveRecord::RecordNotUnique
      # Parallel retry from a flaky-LTE client raced past the find_by above.
      # The unique index on client_uuid prevented the duplicate; return the winner.
      existing = idempotent_existing(uuid)
      return render(json: serialize(existing), status: :ok) if existing
      raise
    end

    if saved && catch_record.photo.attached?
      placements = Catches::PlaceInSlots.call(catch: catch_record)
      Catches::FlagDuplicates.call(catch: catch_record) if catch_record.flags.include?("possible_duplicate")
      FetchCatchConditionsJob.perform_later(catch_id: catch_record.id)
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

  def shares_entry_at?(teammate, at)
    Tournaments::SharedEntryAt.call(
      user_a: current_user, user_b: teammate, club: current_club, at: at || Time.current
    ).present?
  end

  def catch_params
    params.require(:catch).permit(
      :species_id, :length_inches, :captured_at_device, :captured_at_gps,
      :latitude, :longitude, :gps_accuracy_m, :app_build, :client_uuid, :photo, :video, :note
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
