module Tournaments
  class CatchesController < ApplicationController
    before_action :require_sign_in!

    def show
      tournament = current_club.tournaments.find_by(id: params[:tournament_id])
      head :not_found and return if tournament.nil? || tournament.blind?(at: Time.current)

      # An entrants-only tournament hides its leaderboard from non-entrants;
      # the photo modal is reached from that leaderboard, so gate it the same
      # way rather than leaving catch photos reachable by guessing an id.
      head :not_found and return unless tournament_leaderboard_visible?(tournament)

      @catch = Catch.where(user_id: current_club.members.select(:id))
                    .find_by(id: params[:id])
      head :not_found and return if @catch.nil?

      placement_exists = CatchPlacement.active.exists?(
        tournament_id: tournament.id, catch_id: @catch.id
      )
      head :not_found and return unless placement_exists

      @tournament = tournament
    end
  end
end
