class TournamentsController < ApplicationController
  before_action :require_sign_in!

  def index
    scope = current_user.club.tournaments
    scope = scope.where(season_tag: params[:season]) if params[:season].present?
    now = Time.current
    @active_tournaments = scope.where("ends_at IS NULL OR ends_at >= ?", now).order(starts_at: :desc)
    @completed_tournaments = scope.where("ends_at IS NOT NULL AND ends_at < ?", now).order(ends_at: :desc)
    @season_tags = current_user.club.tournaments.where.not(season_tag: nil).distinct.pluck(:season_tag)
  end

  def show
    @tournament = current_user.club.tournaments.find(params[:id])
    @leaderboard = Leaderboards::Build.call(tournament: @tournament)
  end

  def archived
    @tournaments = current_user.club.tournaments
      .where("ends_at IS NOT NULL AND ends_at < ?", 24.hours.ago)
      .order(ends_at: :desc)
  end
end
