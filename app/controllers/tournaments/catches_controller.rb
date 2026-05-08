module Tournaments
  class CatchesController < ApplicationController
    before_action :require_sign_in!

    def show
      tournament = current_club.tournaments.find_by(id: params[:tournament_id])
      head :not_found and return if tournament.nil? || tournament.blind?(at: Time.current)

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
