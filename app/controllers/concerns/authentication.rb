module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :signed_in?
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def signed_in?
    current_user.present?
  end

  def require_sign_in!
    redirect_to new_session_path unless signed_in?
  end

  def sign_in!(user)
    session[:user_id] = user.id
    @current_user = user
  end

  def sign_out!
    session.delete(:user_id)
    @current_user = nil
  end
end
