class Judges::BaseController < ApplicationController
  before_action :require_sign_in!
  before_action :load_tournament
  before_action :require_judge!

  private

  def load_tournament
    @tournament = current_club.tournaments.find(params[:tournament_id])
  end

  def require_judge!
    return if TournamentJudge.exists?(tournament: @tournament, user: current_user)
    return if @tournament.friendly? && current_user.organizer_in?(@tournament.club)
    head :forbidden
  end

  # Catches a judge of @tournament is allowed to see/act on:
  # anything placed in @tournament, plus the club-wide needs_review queue.
  def judgeable_catches
    placed_ids = CatchPlacement.where(tournament_id: @tournament.id).select(:catch_id)
    review_ids = Catch.where(status: :needs_review, user_id: @tournament.club.members.select(:id)).select(:id)
    Catch.where(id: placed_ids).or(Catch.where(id: review_ids))
  end

  def load_catch!
    @catch = judgeable_catches.find(params[:catch_id] || params[:id])
  end
end
