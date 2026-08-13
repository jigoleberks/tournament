class Admin::BaseController < ApplicationController
  layout "admin"
  before_action :require_sign_in!
  before_action :require_organizer!
  # Everything under /admin shows member data — whole namespace opts out
  # (see ApplicationController.disable_turbo_snapshot_cache!).
  disable_turbo_snapshot_cache!

  private

  def require_organizer!
    head :forbidden unless current_user&.organizer_in?(current_club)
  end
end
