class Admin::Clubs::CatchesController < Admin::Clubs::BaseController
  def index
    club_catches = Catch.where(user_id: @foreign_club.members.select(:id))

    @selected_user_id = params[:user_id].presence

    club_catches = club_catches.where(user_id: @selected_user_id) if @selected_user_id

    @members = User.where(id: club_catches.select(:user_id)).order(:name)

    @catches = club_catches
      .includes(:user, :logged_by_user, :species, :catch_placements, photo_attachment: :blob)
      .order(captured_at_device: :desc)
  end
end
