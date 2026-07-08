class Admin::CatchesController < Admin::BaseController
  include ClubCatchIndex
  include CatchDetailEditing

  def index
    load_club_catch_index(current_club)
  end
end
