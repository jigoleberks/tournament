class HomeController < ApplicationController
  before_action :require_sign_in!

  def index
    flash.now[:notice] = "Catch logged — syncing in the background." if params[:queued]
  end
end
