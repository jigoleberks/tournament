class Organizers::BaseController < ApplicationController
  before_action :require_sign_in!
  before_action :require_organizer!

  private

  def require_organizer!
    head :forbidden unless current_user&.organizer_in?(current_club)
  end
end
