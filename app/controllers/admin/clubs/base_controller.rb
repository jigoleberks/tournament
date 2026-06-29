class Admin::Clubs::BaseController < ApplicationController
  layout "admin"
  before_action :require_sign_in!
  before_action :require_site_admin!
  before_action :set_foreign_club

  private

  def set_foreign_club
    @foreign_club = Club.find(params[:club_id])
  end
end
