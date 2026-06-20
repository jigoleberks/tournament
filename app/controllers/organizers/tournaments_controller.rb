class Organizers::TournamentsController < Organizers::BaseController
  include TournamentParams

  before_action :set_tournament, only: [:edit, :update, :destroy, :draw]

  def index
    scope = current_club.tournaments.order(starts_at: :desc)
    now = Time.current
    @active_tournaments = scope.where("ends_at IS NULL OR ends_at >= ?", now)
  end

  def new
    @tournament = current_club.tournaments.new
    3.times { @tournament.scoring_slots.build }
  end

  def create
    @tournament = current_club.tournaments.new(tournament_params)
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

  def draw
    Tournaments::DrawTaggedWinner.call(
      tournament: @tournament,
      drawn_by: current_user,
      force: params[:force].present?
    )
    redirect_to organizers_tournaments_path, notice: "Winner drawn."
  rescue Tournaments::DrawTaggedWinner::NoEligibleCatchesError
    redirect_to organizers_tournaments_path, alert: "No tagged catches to draw from."
  rescue Tournaments::DrawTaggedWinner::PreconditionError => e
    redirect_to organizers_tournaments_path, alert: e.message
  end

  private

  def set_tournament
    @tournament = current_club.tournaments.find(params[:id])
  end
end
