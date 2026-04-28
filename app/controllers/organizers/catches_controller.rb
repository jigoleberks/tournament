class Organizers::CatchesController < Organizers::BaseController
  def index
    @catches = Catch
      .joins(:user)
      .where(users: { club_id: current_user.club_id })
      .includes(:user, :species, :catch_placements, photo_attachment: :blob)
      .order(captured_at_device: :desc)
  end
end
