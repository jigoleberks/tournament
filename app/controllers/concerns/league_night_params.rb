# Shared strong-params for the admin/ and organizers/ league-night schedulers,
# which are twins. Mirrors TournamentParams: one permit-list, so the two forms
# can never drift over which per-column fields they accept.
module LeagueNightParams
  extend ActiveSupport::Concern

  # Everything both columns may set. Main and Side differ in exactly one field —
  # see SIDE_FIELDS below — so the rest lives here and can't drift apart.
  COLUMN_FIELDS = [
    :format, :species_id, :slot_count,
    :target_min_inches, :target_max_inches
  ].freeze

  # :blind_leaderboard is permitted on the Side column ONLY. Main's blind flag is
  # the template's decision, not this screen's, and LeagueNights::Schedule
  # honours whatever :blind_leaderboard key it's handed — so permitting it on
  # Main would let a crafted POST (main[blind_leaderboard]=0) quietly un-blind a
  # Main whose template is blind. Leaving the key out means Main always inherits.
  #
  # Note this is inheritance, NOT a guarantee: nothing requires a paired template
  # to be blind, so the screen reads Main's effective state (template flag OR a
  # forced-blind format) rather than asserting it. See the leak warning in
  # league_night_controller.js.
  MAIN_FIELDS = COLUMN_FIELDS
  SIDE_FIELDS = (COLUMN_FIELDS + [:blind_leaderboard]).freeze

  private

  # Memoized: #create reads this four times to fill LeagueNights::Schedule's
  # keyword arguments, and require + permit is not free.
  def league_night_params
    @league_night_params ||= params.require(:league_night).permit(
      :starts_at, :ends_at, main: MAIN_FIELDS, side: SIDE_FIELDS
    )
  end

  # Formats the scheduler offers. Excludes the solo-only formats (the pair is
  # team mode), Fish Train (its car builder is substantial UI and it has never
  # run on a league night) and Bingo (no scoring slots at all, so the screen's
  # species and count fields are meaningless for it). Both remain available
  # through the normal create flow.
  EXCLUDED_FORMATS = %w[big_fish_season tagged fish_train bingo].freeze

  def schedulable_formats
    ::Tournament.formats.keys - EXCLUDED_FORMATS
  end

  # The night #new was asked to show. Optional ?date=YYYY-MM-DD, so an organizer
  # can load a past night to repair it — the whole point of the repair path is
  # a night that already ran, and NextOccurrence without a date only ever rolls
  # forward. nil means "the next occurrence", which is the default landing.
  def requested_date
    ::Date.parse(params[:date].to_s)
  rescue ::Date::Error
    nil
  end

  # The date #create is actually building on. Detection has to key off THIS,
  # not off the template's next occurrence, or the two disagree: a backdated
  # repair would find nothing on the old date and happily create a second copy
  # of the half that already exists. It also closes a rollover race — a screen
  # opened Tuesday night and submitted after midnight would otherwise be
  # checked against the following week's occurrence.
  def submitted_date
    ::Time.zone.parse(league_night_params[:starts_at].to_s)&.to_date
  rescue ArgumentError
    nil
  end

  # One column's week-specific settings, shaped the way LeagueNights::Schedule
  # wants them. nil when that column wasn't submitted at all — which is the
  # normal case on the repair path, where only the missing half has a form.
  def column_params(column)
    league_night_params[column]&.to_h&.symbolize_keys
  end

  # EXCLUDED_FORMATS is only a picker affordance until it's enforced here. A
  # hand-rolled POST naming a real-but-excluded format ("bingo") creates exactly
  # the league night the exclusion exists to prevent; an unknown one raises
  # ArgumentError from the enum setter, which #create's RecordInvalid rescue
  # does NOT catch, so it 500s instead of re-rendering; and a missing one leaves
  # format nil, which is a NOT NULL column and so fails at the database rather
  # than in validation. Returns the offending value, or nil when all are fine.
  #
  # Takes the same argument hash that goes to LeagueNights::Schedule so it
  # checks the columns actually about to be built — on the repair path there is
  # only one, and the other column's params are ignored entirely.
  def unschedulable_format(args)
    allowed = schedulable_formats
    weeks = [args[:main]]
    weeks << args[:side] if args[:side_template]
    weeks.map { |week| week.to_h[:format].to_s }.find { |value| allowed.exclude?(value) }
  end

  def format_rejection_message(value)
    return "Pick a format for each tournament." if value.blank?
    "\"#{value}\" isn't a format a league night can use."
  end

  # What the operator actually submitted, for redisplay after a failed submit.
  # The form's per-column controls have nothing to fall back on but the
  # templates' own defaults, so without this every format, species, count and
  # time just chosen is silently reverted and only the error text survives.
  def submitted_values
    {
      starts_at: local_datetime_value(league_night_params[:starts_at]),
      ends_at: local_datetime_value(league_night_params[:ends_at]),
      main: column_params(:main) || {},
      side: column_params(:side) || {}
    }
  end

  # datetime-local inputs only accept "YYYY-MM-DDTHH:MM". Echoing back the raw
  # submitted string — which carries seconds and a zone offset whenever the POST
  # came from anywhere but the form itself — leaves the field blank instead.
  def local_datetime_value(value)
    ::Time.zone.parse(value.to_s)&.strftime("%Y-%m-%dT%H:%M")
  rescue ArgumentError
    nil
  end
end
