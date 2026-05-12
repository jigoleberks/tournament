class Admin::Clubs::TournamentTemplatesController < Admin::Clubs::BaseController
  def index
    @templates = @foreign_club.tournament_templates.order(:name)
  end

  def show
    @template = @foreign_club.tournament_templates.find(params[:id])
  end
end
