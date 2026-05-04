class Api::BaseController < ActionController::Base
  protect_from_forgery with: :null_session
  before_action :require_sign_in!

  private

  def current_user
    return @current_user if defined?(@current_user)
    user = User.find_by(id: session[:user_id])
    user = nil if user&.deactivated?
    @current_user = user
  end

  def signed_in?
    current_user.present?
  end

  def require_sign_in!
    head :unauthorized unless signed_in?
  end
end
