class Admin::CatchesController < Admin::BaseController
  def index
    club_catches = Catch.joins(:user).where(users: { club_id: current_user.club_id })

    @members = User.where(id: club_catches.select(:user_id)).order(:name)
    @selected_user_id = params[:user_id].presence

    club_catches = club_catches.where(user_id: @selected_user_id) if @selected_user_id

    @catches = club_catches
      .includes(:user, :species, :catch_placements, photo_attachment: :blob)
      .order(captured_at_device: :desc)
  end
end
