class Admin::TournamentsController < Admin::BaseController
  include TournamentParams

  before_action :set_tournament, only: [:edit, :update, :destroy]

  def index
    scope = current_club.tournaments
    now = Time.current
    @active_tournaments = scope.where("ends_at IS NULL OR ends_at >= ?", now).order(starts_at: :desc)
    @past_tournaments   = scope.where("ends_at IS NOT NULL AND ends_at < ?", now).order(ends_at: :desc)
  end

  def new
    @tournament = current_club.tournaments.new
    3.times { @tournament.scoring_slots.build }
  end

  def create
    @tournament = current_club.tournaments.new(tournament_params)
    if @tournament.save
      redirect_to admin_tournaments_path, notice: "Tournament created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @tournament.scoring_slots.build
  end

  def destroy
    @tournament.destroy
    redirect_to admin_tournaments_path
  end

  def update
    if @tournament.update(tournament_params)
      redirect_to admin_tournaments_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_tournament
    @tournament = current_club.tournaments.find(params[:id])
  end
end
