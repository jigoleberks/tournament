class SeasonPointsController < ApplicationController
  before_action :require_sign_in!

  def show
    @season_tag = params[:season].presence ||
                  ::SeasonPoints::CurrentSeasonTag.call(club: current_club)
    @standings = if @season_tag
      ::SeasonPoints::Standings.call(club: current_club, season_tag: @season_tag)
    else
      []
    end
  end

  def tournaments
    @season_tag = params[:season].presence ||
                  ::SeasonPoints::CurrentSeasonTag.call(club: current_club)
    @tournaments = if @season_tag
      ::SeasonPoints::Tournaments.call(club: current_club, season_tag: @season_tag)
    else
      []
    end
  end
end
