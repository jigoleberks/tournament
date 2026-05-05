class Admin::TournamentTemplatesController < Admin::BaseController
  before_action :load_template, only: [:edit, :update, :destroy, :clone]

  def index
    @templates = current_user.club.tournament_templates.order(:name)
  end

  def new
    @template = current_user.club.tournament_templates.new
    3.times { @template.tournament_template_scoring_slots.build }
  end

  def create
    @template = current_user.club.tournament_templates.new(template_params)
    if @template.save
      redirect_to admin_tournament_templates_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @template.tournament_template_scoring_slots.build
  end

  def destroy
    @template.destroy
    redirect_to admin_tournament_templates_path, notice: "Template deleted."
  end

  def update
    if @template.update(template_params)
      redirect_to admin_tournament_templates_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def clone
    TournamentTemplates::Clone.call(
      template: @template,
      starts_at: params[:starts_at],
      ends_at: params[:ends_at]
    )
    redirect_to admin_tournaments_path, notice: "Cloned."
  end

  private

  def load_template
    @template = current_user.club.tournament_templates.find(params[:id])
  end

  def template_params
    params.require(:tournament_template).permit(
      :name, :mode, :default_duration_days,
      :default_weekday, :default_start_time, :default_end_time,
      :awards_season_points,
      tournament_template_scoring_slots_attributes: [:id, :species_id, :slot_count, :_destroy]
    )
  end
end
