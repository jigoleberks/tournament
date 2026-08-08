class Admin::Clubs::BaseController < ApplicationController
  layout "admin"
  before_action :require_sign_in!
  before_action :require_site_admin!
  before_action :set_foreign_club
  # Cross-club member management shows emails/codes too — keep it out of
  # Turbo's snapshot cache, same as Admin::BaseController.
  before_action { @disable_turbo_snapshot_cache = true }

  private

  def set_foreign_club
    @foreign_club = Club.find(params[:club_id])
  end
end
