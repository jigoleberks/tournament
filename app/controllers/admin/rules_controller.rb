class Admin::RulesController < Admin::BaseController
  ALLOWED_SEASONS = %w[open_water ice].freeze

  def index
    @open_water_revision = ClubRulesRevision.latest_for(club: current_club, season: :open_water)
    @ice_revision        = ClubRulesRevision.latest_for(club: current_club, season: :ice)
  end

  def set_active_season
    season = params[:season].to_s
    unless ALLOWED_SEASONS.include?(season)
      head :unprocessable_entity
      return
    end
    current_club.update!(active_rules_season: season)
    redirect_to admin_rules_path, notice: "Active season set to #{season.humanize}."
  end
end
