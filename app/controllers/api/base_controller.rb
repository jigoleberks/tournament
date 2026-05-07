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

  def current_membership
    return @current_membership if defined?(@current_membership)
    @current_membership = pick_membership(current_user, preferred_club_id: session[:current_club_id])
  end

  def current_club
    current_membership&.club
  end

  def signed_in?
    current_user.present?
  end

  def require_sign_in!
    head :unauthorized unless signed_in?
  end

  def pick_membership(user, preferred_club_id:)
    return nil unless user
    memberships = user.club_memberships.active
    if preferred_club_id
      preferred = memberships.find_by(club_id: preferred_club_id)
      return preferred if preferred
    end
    memberships.first
  end
end
