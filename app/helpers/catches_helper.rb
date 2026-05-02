module CatchesHelper
  # An organizer of the club, or a judge of any tournament where this catch
  # is placed, may open the catch detail page (photo, video, GPS, etc.).
  # Regular members can see catches on the leaderboard but not the detail.
  def can_view_catch?(catch_record)
    return false if current_user.nil?
    return true  if catch_record.user_id == current_user.id
    return true  if current_user.organizer?
    judge_tournament_ids = TournamentJudge.where(user: current_user).pluck(:tournament_id)
    catch_tournament_ids = catch_record.catch_placements.pluck(:tournament_id).uniq
    (judge_tournament_ids & catch_tournament_ids).any?
  end

  # Cheap form for the leaderboard partial: any organizer, or a judge of
  # the given tournament. (Doesn't load the catch's placements.)
  def can_open_catches_in?(tournament)
    return false if current_user.nil? || tournament.nil?
    current_user.organizer? || TournamentJudge.exists?(tournament: tournament, user: current_user)
  end

  FLAG_LABELS = {
    "missing_gps"   => "no GPS",
    "clock_skew"    => "clock mismatch",
    "out_of_bounds" => "outside lake"
  }.freeze

  def flag_label(flag)
    FLAG_LABELS.fetch(flag, flag.humanize.downcase)
  end
end
