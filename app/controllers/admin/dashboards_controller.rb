class Admin::DashboardsController < Admin::BaseController
  def index
    return unless current_user&.admin?

    @total_clubs          = Club.count
    @total_active_members = User.active.count
    @active_tournaments   = Tournament.where("ends_at IS NULL OR ends_at >= ?", Time.current).count
    @catches_last_7_days  = Catch.where(captured_at_device: 7.days.ago..).count
  end
end
