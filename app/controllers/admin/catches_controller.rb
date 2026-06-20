class Admin::CatchesController < Admin::BaseController
  include ClubCatchIndex

  def index
    load_club_catch_index(current_club)
  end
end
