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

  # :blind_leaderboard is permitted on the Side column ONLY. Main is always
  # blind — that's the premise the screen's same-species leak warning rests on —
  # and LeagueNights::Schedule honours whatever :blind_leaderboard key it's
  # handed, so permitting it on Main would let a crafted POST
  # (main[blind_leaderboard]=0) quietly un-blind Main. Leaving the key out means
  # Main always inherits the template's flag.
  MAIN_FIELDS = COLUMN_FIELDS
  SIDE_FIELDS = (COLUMN_FIELDS + [:blind_leaderboard]).freeze

  private

  def league_night_params
    params.require(:league_night).permit(
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
end
