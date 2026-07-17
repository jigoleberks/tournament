class Api::BaseController < ActionController::Base
  include Authentication

  protect_from_forgery with: :null_session
  before_action :require_sign_in!

  # WebKit can POST with no body at all when it fails to stream a file-backed
  # IndexedDB blob (2026-07-15: 595 empty-bodied 400s). Rails' default
  # ParameterMissing response is HTML, which offline/sync.js can't turn into a
  # readable failure reason. Answer in the JSON shape the sync client expects.
  rescue_from ActionController::ParameterMissing do |e|
    render json: { errors: ["Request arrived empty (#{e.param} missing) — the upload may have failed on the device. Try again from Pending catches."] },
           status: :bad_request
  end

  private

  # API clients get a 401 instead of the concern's redirect to the sign-in page.
  def require_sign_in!
    head :unauthorized unless signed_in?
  end
end
