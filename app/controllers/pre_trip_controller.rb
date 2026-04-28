class PreTripController < ApplicationController
  before_action :require_sign_in!

  def show
    @active_tournament_count = Tournaments::ActiveForUser.call(user: current_user).size
  end
end
