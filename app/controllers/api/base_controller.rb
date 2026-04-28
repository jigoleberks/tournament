class Api::BaseController < ActionController::Base
  protect_from_forgery with: :null_session
  before_action :require_sign_in!

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def signed_in?
    current_user.present?
  end

  def require_sign_in!
    head :unauthorized unless signed_in?
  end
end
