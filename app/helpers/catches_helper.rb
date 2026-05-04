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

  # Staff-eyes-only check used to gate review-oriented UI (e.g. the
  # possible-duplicate flag). Catch owners do NOT qualify here.
  def can_review_catch?(catch_record)
    return false if current_user.nil?
    return true  if current_user.organizer?
    # Helper instances are per-request, so this ivar memo is request-scoped —
    # the TournamentJudge lookup runs once per request, not once per catch.
    judge_ids = (@_judge_tournament_ids ||= TournamentJudge.where(user: current_user).pluck(:tournament_id))
    return false if judge_ids.empty?
    catch_tournament_ids = catch_record.catch_placements.pluck(:tournament_id).uniq
    (judge_ids & catch_tournament_ids).any?
  end

  # Member-facing flag list: drops review-only flags (e.g. possible_duplicate)
  # unless the current viewer is staff for this catch.
  def visible_flags_for(catch_record)
    flags = Array(catch_record.flags)
    return flags unless flags.include?("possible_duplicate")
    return flags if can_review_catch?(catch_record)
    flags - ["possible_duplicate"]
  end

  FLAG_LABELS = {
    "missing_gps"        => "no GPS",
    "clock_skew"         => "clock mismatch",
    "out_of_bounds"      => "outside local",
    "out_of_province"    => "outside Saskatchewan",
    "possible_duplicate" => "possible duplicate"
  }.freeze

  def flag_label(flag)
    FLAG_LABELS.fetch(flag, flag.humanize.downcase)
  end

  # Returns a URL for the given day-cell on the calendar. The URL encodes the
  # next selection state per `next_range`, while passing other params (species,
  # sort, page, etc.) through unchanged. Drops Rails-internal :controller and
  # :action keys that may show up in `request.query_parameters`.
  def month_calendar_link_url(day, current_start:, current_end:, params:, path_helper:)
    target_start, target_end = next_range(day, current_start, current_end)
    cleaned = params.to_h.with_indifferent_access.except(:controller, :action)
    public_send(path_helper, cleaned.merge(
      start: target_start&.iso8601,
      end: target_end&.iso8601
    ).compact)
  end

  # Returns [target_start, target_end] given a tapped day and the current
  # selection state. Implements the tap-rule table:
  #   - no selection         → single day on tapped
  #   - single day, same tap → no change
  #   - single day, diff tap → range (min/max of the two)
  #   - existing range, tap  → reset to single day on tapped
  def next_range(day, current_start, current_end)
    return [day, day] if current_start.nil?
    return [current_start, current_end] if current_start == current_end && day == current_start
    return [[current_start, day].min, [current_start, day].max] if current_start == current_end
    [day, day]
  end

  # CSS class for a single calendar day cell, given the day and the current
  # selection range. Caller adds layout classes (size, padding) on top.
  def catch_calendar_day_classes(day:, selected_start:, selected_end:, in_displayed_month:)
    base = ["relative", "flex", "items-center", "justify-center", "h-10", "text-sm"]
    return base + ["text-slate-600"] unless in_displayed_month

    classes = base + ["text-slate-200", "rounded"]
    if selected_start && day >= selected_start && day <= (selected_end || selected_start)
      if day == selected_start && day == selected_end
        classes += ["bg-blue-600", "text-white", "rounded"]
      elsif day == selected_start
        classes += ["bg-blue-600", "text-white", "rounded-l", "rounded-r-none"]
      elsif day == selected_end
        classes += ["bg-blue-600", "text-white", "rounded-r", "rounded-l-none"]
      else
        classes += ["bg-blue-600/40", "rounded-none"]
      end
    end
    classes += ["ring-2", "ring-blue-400"] if day == Date.current
    classes.join(" ")
  end

  # The 6×7 grid of dates that fills the visible month, including dim
  # leading/trailing days from the prior/next months. Returns an array of
  # arrays (rows of 7 Date objects).
  def catch_calendar_grid(month_start)
    first = month_start.beginning_of_month
    grid_start = first.beginning_of_week(:sunday)
    last = month_start.end_of_month
    grid_end = last.end_of_week(:sunday)
    (grid_start..grid_end).each_slice(7).to_a
  end
end
