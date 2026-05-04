module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :signed_in?
  end

  def current_user
    return @current_user if defined?(@current_user)
    user = User.find_by(id: session[:user_id])
    if user&.deactivated?
      session.delete(:user_id)
      user = nil
    end
    @current_user = user
  end

  def signed_in?
    current_user.present?
  end

  def require_sign_in!
    redirect_to new_session_path unless signed_in?
  end

  def sign_in!(user)
    reset_session
    session[:user_id] = user.id
    @current_user = user
  end

  def sign_out!
    session.delete(:user_id)
    @current_user = nil
  end
end
