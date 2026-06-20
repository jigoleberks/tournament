class Api::BaseController < ActionController::Base
  include Authentication

  protect_from_forgery with: :null_session
  before_action :require_sign_in!

  private

  # API clients get a 401 instead of the concern's redirect to the sign-in page.
  def require_sign_in!
    head :unauthorized unless signed_in?
  end
end
