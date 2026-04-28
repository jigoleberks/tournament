class TournamentsController < ApplicationController
  before_action :require_sign_in!

  def index
    scope = current_user.club.tournaments.order(starts_at: :desc)
    scope = scope.where(season_tag: params[:season]) if params[:season].present?
    @tournaments = scope
    @season_tags = current_user.club.tournaments.where.not(season_tag: nil).distinct.pluck(:season_tag)
  end

  def show
    @tournament = current_user.club.tournaments.find(params[:id])
    @leaderboard = Leaderboards::Build.call(tournament: @tournament)
  end
end
