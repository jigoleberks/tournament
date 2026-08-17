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

    # A half-scheduled night is the one place creating a single tournament is
    # legitimate: repairing a night that already ran with only one of its two
    # tournaments (2026-08-06 was a Main with no Side). Whichever half is
    # missing becomes the "main" of the call, so Schedule builds exactly one and
    # leaves the tournament that already exists untouched.
    #
    # Guarded on the pair still being there: partially_scheduled? is XOR on
    # presence, so an UNPAIRED template reports "half done" the moment anything
    # exists for its week, when in fact nothing is missing. load_template turns
    # unpaired templates away before this runs — the guard keeps the create path
    # from depending on that staying true.
    args =
      if occurrence.partially_scheduled? && @template.paired_template.present?
        missing = occurrence.existing_main.present? ? :side : :main
        { main_template: missing == :side ? @template.paired_template : @template,
          side_template: nil, main: column_params(missing), side: nil }
      else
        { main_template: @template, side_template: @template.paired_template,
          main: column_params(:main), side: column_params(:side) }
      end

    if (rejected = unschedulable_format(args))
      return render_new_with_error(format_rejection_message(rejected))
    end

    tournaments = LeagueNights::Schedule.call(
      starts_at: league_night_params[:starts_at],
      ends_at: league_night_params[:ends_at],
      **args
    )
    redirect_to edit_organizers_tournament_path(tournaments.first), notice: "League night scheduled."
  rescue ActiveRecord::RecordInvalid => e
    render_new_with_error(e.message)
  end

  private

  # Both failure paths come back here. @submitted carries the operator's own
  # choices into the re-render: rebuilding @occurrence alone hands back a
  # pristine form, throwing away every format, species, count and time just
  # picked and leaving only the error text behind.
  def render_new_with_error(message)
    @occurrence = LeagueNights::NextOccurrence.call(template: @template)
    @formats = schedulable_formats
    @submitted = submitted_values
    @error = message
    render :new, status: :unprocessable_entity
  end

  def load_template
    @template = current_club.tournament_templates.find(params[:tournament_template_id])
    # paired_template rather than paired?: the latter only reads the raw id, and
    # everything downstream here dereferences the record itself.
    return if @template.paired_template.present?
    redirect_to organizers_tournament_templates_path,
                alert: "That template isn't paired with another one."
  end
end
