class Organizers::TournamentTemplatesController < Organizers::BaseController
  include TemplateParams

  before_action :load_template, only: [:edit, :update, :destroy, :clone]

  def index
    all = current_club.tournament_templates.order(:name).to_a
    # A pair is one league night, so show it once: drop the partner of any
    # template already in the list.
    seen = []
    @templates = all.reject do |template|
      hide = template.paired? && seen.include?(template.paired_template_id)
      seen << template.id
      hide
    end
  end

  def new
    @template = current_club.tournament_templates.new
    3.times { @template.tournament_template_scoring_slots.build }
  end

  def create
    @template = current_club.tournament_templates.new(template_params)
    if @template.save
      redirect_to organizers_tournament_templates_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @template.tournament_template_scoring_slots.build
  end

  def destroy
    @template.destroy
    redirect_to organizers_tournament_templates_path, notice: "Template deleted."
  end

  def update
    if @template.update(template_params)
      redirect_to organizers_tournament_templates_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def clone
    TournamentTemplates::Clone.call(
      template: @template,
      starts_at: params[:starts_at],
      ends_at: params[:ends_at],
      season_tag: @template.season_tag
    )
    redirect_to organizers_tournaments_path, notice: "Cloned."
  end

  private

  def load_template
    @template = current_club.tournament_templates.find(params[:id])
  end
end
