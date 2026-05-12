class Admin::Clubs::TournamentsController < Admin::Clubs::BaseController
  def index
    @tournaments = @foreign_club.tournaments.order(starts_at: :desc)
  end
end
