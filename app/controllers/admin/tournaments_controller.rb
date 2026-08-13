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
      # Flipping the backfill flag ON is the on-site fix for a missed entrant:
      # sweep every current entrant's already-logged in-window catches now.
      # Re-saving with it already on re-runs nothing (no saved_change).
      if @tournament.saved_change_to_backfill_late_entrants? && @tournament.backfill_late_entrants?
        Tournaments::BackfillEntrantCatches.call(tournament: @tournament)
      end
      redirect_to admin_tournaments_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def results
    @tournament = current_club.tournaments.find(params[:id])
    @leaderboard = Leaderboards::Build.call(tournament: @tournament)
    render layout: "print"
  end

  private

  def set_tournament
    @tournament = current_club.tournaments.find(params[:id])
  end

  # The shared TournamentParams permit-list intentionally omits
  # :backfill_late_entrants — lifting the no-backfill rule is admin-panel-only,
  # so only this controller permits it. This divergence from the organizers
  # permit-list is deliberate; don't "fix" it by moving the key into the concern.
  def tournament_params
    super.merge(params.require(:tournament).permit(:backfill_late_entrants))
  end
end
