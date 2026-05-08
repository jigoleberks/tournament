class Organizers::CatchesController < Organizers::BaseController
  def index
    club_catches = Catch.where(user_id: current_club.members.select(:id))

    @members = User.where(id: club_catches.select(:user_id)).order(:name)
    @selected_user_id = params[:user_id].presence

    club_catches = club_catches.where(user_id: @selected_user_id) if @selected_user_id

    @catches = club_catches
      .includes(:user, :logged_by_user, :species, :catch_placements, photo_attachment: :blob)
      .order(captured_at_device: :desc)
  end
end
