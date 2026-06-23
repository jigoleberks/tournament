class Admin::Clubs::CatchesController < Admin::Clubs::BaseController
  include ClubCatchIndex

  def index
    load_club_catch_index(@foreign_club)
  end
end
