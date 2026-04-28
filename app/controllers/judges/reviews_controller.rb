class Judges::ReviewsController < Judges::BaseController
  before_action :load_catch!

  def create
    Catches::ApplyJudgeAction.call(
      tournament: @tournament, catch: @catch, judge: current_user,
      action: params[:action_kind], note: params[:note]
    )
    redirect_to judges_tournament_catch_path(tournament_id: @tournament.id, id: @catch.id)
  end
end
