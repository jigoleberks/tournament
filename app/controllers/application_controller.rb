class ApplicationController < ActionController::Base
  include Authentication
  allow_browser versions: :modern

  before_action :touch_last_seen
  helper_method :tournament_leaderboard_visible?

  private

  def tournament_leaderboard_visible?(tournament)
    return false unless current_user && tournament
    return true unless tournament.entrants_only_leaderboard?
    return true if current_user.admin?
    return true if current_user.organizer_in?(tournament.club)
    return true if TournamentJudge.exists?(tournament_id: tournament.id, user_id: current_user.id)
    TournamentEntryMember.joins(:tournament_entry)
      .exists?(tournament_entries: { tournament_id: tournament.id }, user_id: current_user.id)
  end

  def touch_last_seen
    current_user&.touch_last_seen!
  end
end
