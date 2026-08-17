class Organizers::LeagueNightsController < Organizers::BaseController
  include LeagueNightParams

  before_action :load_template

  def new
    @occurrence = LeagueNights::NextOccurrence.call(template: @template)
    @formats = schedulable_formats
  end

  def create
    occurrence = LeagueNights::NextOccurrence.call(template: @template)
    if occurrence.fully_scheduled?
      redirect_to organizers_tournament_templates_path,
                  alert: "That week is already scheduled." and return
    end

    tournaments = LeagueNights::Schedule.call(
      main_template: @template,
      side_template: occurrence.existing_side ? nil : @template.paired_template,
      starts_at: league_night_params[:starts_at],
      ends_at: league_night_params[:ends_at],
      main: league_night_params[:main]&.to_h&.symbolize_keys,
      side: league_night_params[:side]&.to_h&.symbolize_keys
    )
    redirect_to edit_organizers_tournament_path(tournaments.first), notice: "League night scheduled."
  rescue ActiveRecord::RecordInvalid => e
    @occurrence = LeagueNights::NextOccurrence.call(template: @template)
    @formats = schedulable_formats
    @error = e.message
    render :new, status: :unprocessable_entity
  end

  private

  def load_template
    @template = current_club.tournament_templates.find(params[:tournament_template_id])
    # paired_template rather than paired?: the latter only reads the raw id, and
    # everything downstream here dereferences the record itself.
    return if @template.paired_template.present?
    redirect_to organizers_tournament_templates_path,
                alert: "That template isn't paired with another one."
  end
end
