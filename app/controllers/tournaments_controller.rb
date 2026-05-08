class TournamentsController < ApplicationController
  before_action :require_sign_in!

  def index
    scope = current_club.tournaments.order(starts_at: :desc)
    scope = scope.where(season_tag: params[:season]) if params[:season].present?
    now = Time.current
    @active_tournaments = scope.where("ends_at IS NULL OR ends_at >= ?", now)
    @completed_tournaments = scope.where("ends_at IS NOT NULL AND ends_at < ?", now)
    @season_tags = current_club.tournaments.where.not(season_tag: nil).distinct.pluck(:season_tag)
  end

  def show
    @tournament = current_club.tournaments.find(params[:id])
    @leaderboard = Leaderboards::Build.call(tournament: @tournament)
    @viewer_scope = Leaderboards::ViewerScope.for(tournament: @tournament, user: current_user)
  end

  def archived
    @tournaments = current_club.tournaments
      .where("ends_at IS NOT NULL AND ends_at < ?", 24.hours.ago)
      .order(ends_at: :desc)
  end
end
