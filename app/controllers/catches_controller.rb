class CatchesController < ApplicationController
  before_action :require_sign_in!

  def index
    @catches = current_user.catches
                           .includes(:species, photo_attachment: :blob)
                           .order(captured_at_device: :desc)
  end

  def show
    @catch = Catch.joins(:user)
                  .where(users: { club_id: current_user.club_id })
                  .find(params[:id])
    head :forbidden and return unless authorized_to_view?(@catch)
    @action_tournament = resolve_action_tournament(@catch)
  end

  def new
    @catch = current_user.catches.build(captured_at_device: Time.current,
                                         client_uuid: SecureRandom.uuid)
    @species = current_user.club.species.order(:name)
  end

  def create
    @catch = current_user.catches.build(catch_params)
    @catch.status = :synced
    @catch.synced_at = Time.current

    if @catch.save && @catch.photo.attached?
      Catches::PlaceInSlots.call(catch: @catch)
      redirect_to root_path, notice: "Catch logged"
    else
      @catch.errors.add(:photo, "is required") unless @catch.photo.attached?
      @species = current_user.club.species.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  private

  def authorized_to_view?(catch_record)
    return true if catch_record.user_id == current_user.id
    return true if current_user.organizer?
    judge_tournament_ids = TournamentJudge.where(user: current_user).pluck(:tournament_id)
    catch_tournament_ids = catch_record.catch_placements.pluck(:tournament_id).uniq
    (judge_tournament_ids & catch_tournament_ids).any?
  end

  # Tournament to act in (DQ / length edit) from this catch's show page.
  # Prefer ?t= when supplied and the user has authority there; otherwise
  # the first placement the user can act on. Returns nil if none.
  def resolve_action_tournament(catch_record)
    candidate_ids = catch_record.catch_placements.pluck(:tournament_id).uniq
    return nil if candidate_ids.empty?
    tournaments = current_user.club.tournaments.where(id: candidate_ids)
    preferred = tournaments.find_by(id: params[:t])
    [preferred, *tournaments].compact.find { |t| can_act_on?(t) }
  end

  def can_act_on?(tournament)
    return true if tournament.friendly? && current_user.organizer?
    TournamentJudge.exists?(tournament: tournament, user: current_user)
  end

  def catch_params
    params.require(:catch).permit(
      :species_id, :length_inches, :captured_at_device, :captured_at_gps,
      :latitude, :longitude, :gps_accuracy_m, :app_build, :client_uuid, :photo
    )
  end
end
