class Admin::BaseController < ApplicationController
  layout "admin"
  before_action :require_sign_in!
  before_action :require_organizer!
  # Shared club laptop: after sign-out, Back must not replay member emails /
  # live sign-in codes from Turbo's snapshot cache (restoration visits never
  # hit the server). Everything under /admin shows member data, so the whole
  # namespace opts out — same controller-side switch Organizers::Members uses,
  # honored by both layouts.
  before_action { @disable_turbo_snapshot_cache = true }

  private

  def require_organizer!
    head :forbidden unless current_user&.organizer_in?(current_club)
  end
end
