# Shared catch-history index for the admin/, organizers/, and admin/clubs/
# catches controllers (otherwise byte-identical save for which club they scope
# to). Keeps the eager-load chain that prevents N+1s on the catch grid in one
# place so it can't drift between the three.
module ClubCatchIndex
  extend ActiveSupport::Concern

  private

  def load_club_catch_index(club)
    club_catches = Catch.where(user_id: club.members.select(:id))

    @members = User.where(id: club_catches.select(:user_id)).order(:name)
    @selected_user_id = params[:user_id].presence

    club_catches = club_catches.where(user_id: @selected_user_id) if @selected_user_id

    @catches = club_catches
      .includes(:user, :logged_by_user, :species, :catch_placements, photo_attachment: :blob, reference_photo_attachment: :blob)
      .order(captured_at_device: :desc)
  end
end
