class Organizers::TournamentsController < Organizers::BaseController
  before_action :set_tournament, only: [:edit, :update, :destroy]

  def index
    @tournaments = current_user.club.tournaments.order(starts_at: :desc)
  end

  def new
    @tournament = current_user.club.tournaments.new
    3.times { @tournament.scoring_slots.build }
  end

  def create
    @tournament = current_user.club.tournaments.new(tournament_params)
    if @tournament.save
      redirect_to organizers_tournaments_path, notice: "Tournament created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @tournament.scoring_slots.build
  end

  def destroy
    @tournament.destroy
    redirect_to organizers_tournaments_path
  end

  def update
    if @tournament.update(tournament_params)
      redirect_to organizers_tournaments_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_tournament
    @tournament = current_user.club.tournaments.find(params[:id])
  end

  def tournament_params
    params.require(:tournament).permit(
      :name, :kind, :mode, :starts_at, :ends_at, :season_tag, :requires_release_video,
      scoring_slots_attributes: [:id, :species_id, :slot_count, :_destroy]
    )
  end
end
