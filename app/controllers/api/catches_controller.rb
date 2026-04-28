class Api::CatchesController < Api::BaseController
  CLOCK_SKEW_THRESHOLD = 5.minutes

  def create
    existing = current_user.catches.find_by(client_uuid: params.dig(:catch, :client_uuid))
    if existing
      return render(json: serialize(existing), status: :ok)
    end

    catch_record = current_user.catches.build(catch_params)
    flags = compute_flags(catch_record)
    catch_record.status = flags.empty? ? :synced : :needs_review
    catch_record.synced_at = Time.current

    if catch_record.save && catch_record.photo.attached?
      placements = Catches::PlaceInSlots.call(catch: catch_record)
      render json: serialize(catch_record, placements: placements[:created], flags: flags), status: :created
    else
      catch_record.errors.add(:photo, "is required") unless catch_record.photo.attached?
      render json: { errors: catch_record.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def catch_params
    params.require(:catch).permit(
      :species_id, :length_inches, :captured_at_device, :captured_at_gps,
      :latitude, :longitude, :gps_accuracy_m, :app_build, :client_uuid, :photo, :video
    )
  end

  def compute_flags(catch_record)
    flags = []
    flags << "missing_gps" if catch_record.latitude.nil?
    if catch_record.captured_at_device && catch_record.captured_at_gps
      skew = (catch_record.captured_at_device - catch_record.captured_at_gps).abs
      flags << "clock_skew" if skew > CLOCK_SKEW_THRESHOLD
    end
    flags
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
