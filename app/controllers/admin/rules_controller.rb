class Admin::RulesController < Admin::BaseController
  ALLOWED_SEASONS = %w[open_water ice].freeze

  def index
    @open_water_revision = ClubRulesRevision.latest_for(club: current_club, season: :open_water)
    @ice_revision        = ClubRulesRevision.latest_for(club: current_club, season: :ice)
  end

  def new
    season = params[:season].to_s
    season = "open_water" unless ALLOWED_SEASONS.include?(season)
    @revision = ClubRulesRevision.new(club: current_club, season: season,
                                      edited_by_user: current_user)
  end

  def create
    @revision = ClubRulesRevision.new(revision_params)
    @revision.club = current_club
    @revision.edited_by_user = current_user
    if @revision.save
      redirect_to admin_rules_path, notice: "New revision saved."
    else
      render :new, status: :unprocessable_entity
    end
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

  def history
    @season = params[:season].to_s
    @season = "open_water" unless ALLOWED_SEASONS.include?(@season)
    @revisions = current_club.rules_revisions.where(season: @season).order(created_at: :desc)
  end

  def show
    @revision = current_club.rules_revisions.find_by(id: params[:id])
    head :not_found and return if @revision.nil?
  end

  private

  def revision_params
    params.require(:club_rules_revision).permit(:season, :body)
  end
end
