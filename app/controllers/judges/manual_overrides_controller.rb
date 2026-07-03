class Judges::ManualOverridesController < Judges::BaseController
  include LengthParamParsing

  before_action :load_catch!

  def new
  end

  def create
    Catches::ApplyJudgeAction.call(
      tournament: @tournament, catch: @catch, judge: current_user, action: :manual_override,
      note: params[:note],
      length_inches: resolved_length_inches,
      length_unit: resolved_length_unit,
      species_id: params[:species_id].presence&.to_i,
      slot_index: params[:slot_index].presence&.to_i,
      entry_id: params[:entry_id].presence&.to_i
    )
    redirect_to judges_tournament_catch_path(tournament_id: @tournament.id, id: @catch.id)
  end
end
