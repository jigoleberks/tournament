module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :signed_in?, :current_club, :current_membership
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

  def current_membership
    return @current_membership if defined?(@current_membership)
    @current_membership = resolve_current_membership
  end

  def current_club
    current_membership&.club
  end

  def signed_in?
    current_user.present?
  end

  def require_sign_in!
    redirect_to new_session_path unless signed_in?
  end

  def sign_in!(user, club: nil)
    reset_session
    session[:user_id] = user.id
    chosen = pick_membership(user, preferred_club_id: club&.id)
    session[:current_club_id] = chosen&.club_id
    @current_user = user
    @current_membership = chosen
  end

  def sign_out!
    session.delete(:user_id)
    session.delete(:current_club_id)
    @current_user = nil
    @current_membership = nil
  end

  private

  # Verify session[:current_club_id] points at a club the user has an active
  # membership in. If not (tampered cookie, deactivated membership, stale
  # session after a club change), fall back to the user's first active
  # membership. Returns nil only if the user has no active memberships.
  def resolve_current_membership
    return nil unless current_user
    pick_membership(current_user, preferred_club_id: session[:current_club_id])
  end

  def pick_membership(user, preferred_club_id:)
    memberships = user.club_memberships.active
    if preferred_club_id
      preferred = memberships.find_by(club_id: preferred_club_id)
      return preferred if preferred
    end
    memberships.first
  end
end
