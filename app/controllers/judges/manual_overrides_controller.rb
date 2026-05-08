class Judges::ManualOverridesController < Judges::BaseController
  before_action :load_catch!

  def new
  end

  def create
    Catches::ApplyJudgeAction.call(
      tournament: @tournament, catch: @catch, judge: current_user, action: :manual_override,
      note: params[:note],
      length_inches: resolved_length_inches,
      species_id: params[:species_id].presence&.to_i,
      slot_index: params[:slot_index].presence&.to_i,
      entry_id: params[:entry_id].presence&.to_i
    )
    redirect_to judges_tournament_catch_path(tournament_id: @tournament.id, id: @catch.id)
  end

  private

  # Accept either:
  #   - legacy: length_inches=19.75 (raw inches)
  #   - new:    length=50 + length_unit=centimeters (or inches)
  def resolved_length_inches
    if params[:length].present?
      raw = params[:length].to_d
      params[:length_unit] == "centimeters" ? raw / LengthHelper::CM_PER_INCH : raw
    else
      params[:length_inches]&.to_d
    end
  end
end
