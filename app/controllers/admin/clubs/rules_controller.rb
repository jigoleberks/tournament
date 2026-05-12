class Admin::Clubs::RulesController < Admin::Clubs::BaseController
  ALLOWED_SEASONS = %w[open_water ice].freeze

  def index
    @open_water_revision = ClubRulesRevision.latest_for(club: @foreign_club, season: :open_water)
    @ice_revision        = ClubRulesRevision.latest_for(club: @foreign_club, season: :ice)
  end

  def show
    @revision = @foreign_club.rules_revisions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def history
    @season = params[:season].to_s
    @season = "open_water" unless ALLOWED_SEASONS.include?(@season)
    @revisions = @foreign_club.rules_revisions
                              .includes(:edited_by_user)
                              .where(season: @season)
                              .order(created_at: :desc)
  end
end
