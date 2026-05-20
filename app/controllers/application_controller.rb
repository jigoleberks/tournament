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
    return true if organizer_club_ids.include?(tournament.club_id)
    return true if judged_tournament_ids.include?(tournament.id)
    entered_tournament_ids.include?(tournament.id)
  end

  # The three helpers below are request-memoized so rendering a list of
  # tournaments (home, index, archived, season points) costs at most one
  # query each instead of three per row. They are only built when an
  # entrants-only tournament is actually encountered, so a page with none
  # still issues zero extra queries.
  def organizer_club_ids
    @organizer_club_ids ||=
      current_user.club_memberships.active.where(role: :organizer).pluck(:club_id).to_set
  end

  def judged_tournament_ids
    @judged_tournament_ids ||=
      TournamentJudge.where(user_id: current_user.id).pluck(:tournament_id).to_set
  end

  def entered_tournament_ids
    @entered_tournament_ids ||=
      TournamentEntryMember.joins(:tournament_entry)
        .where(user_id: current_user.id)
        .pluck("tournament_entries.tournament_id").to_set
  end

  def touch_last_seen
    current_user&.touch_last_seen!
  end
end
