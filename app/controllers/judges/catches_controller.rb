class Judges::CatchesController < Judges::BaseController
  before_action :load_catch!, only: :show

  def index
    @catches = judgeable_catches
      .joins(:user)
      .order(Arel.sql("CASE WHEN catches.status = #{Catch.statuses[:needs_review]} THEN 0 ELSE 1 END"), captured_at_device: :desc)
  end

  def show
    @actions = @catch.judge_actions.order(:created_at)
  end
end
