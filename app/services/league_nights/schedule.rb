module LeagueNights
  # Creates a league night: both tournaments at once, already linked, in one
  # transaction so a validation failure on either side leaves nothing behind.
  #
  # The scheduler screen supplies only what varies week to week — date, times,
  # and each column's format, species and slot count. Name, mode, season tag,
  # season points, entrants-only and Main's blind flag are inherited from the
  # templates, which is where those decisions live. Templates carry no local/
  # judged columns of their own, so those two are left unset here and simply
  # take Tournament's own defaults (local: true, judged: false).
  class Schedule
    def self.call(main_template:, side_template:, starts_at:, ends_at:, main:, side:)
      new(main_template: main_template, side_template: side_template,
          starts_at: starts_at, ends_at: ends_at, main: main, side: side).call
    end

    def initialize(main_template:, side_template:, starts_at:, ends_at:, main:, side:)
      @main_template = main_template
      @side_template = side_template
      @starts_at = starts_at
      @ends_at = ends_at
      @main = main || {}
      @side = side || {}
    end

    def call
      group_id = @side_template ? SecureRandom.uuid : nil

      ::Tournament.transaction do
        main_tournament = build(@main_template, @main, group_id)
        main_tournament.save!
        next [main_tournament] if @side_template.nil?

        side_tournament = build(@side_template, @side, group_id)
        side_tournament.save!
        [main_tournament, side_tournament]
      end
    end

    private

    def build(template, week, group_id)
      tournament = template.club.tournaments.new(
        {
          name: template.name,
          mode: template.mode,
          starts_at: @starts_at,
          ends_at: @ends_at,
          season_tag: template.season_tag,
          template_source_id: template.id,
          awards_season_points: template.awards_season_points,
          entrants_only_leaderboard: template.entrants_only_leaderboard,
          blind_leaderboard: week.key?(:blind_leaderboard) ? week[:blind_leaderboard] : template.blind_leaderboard,
          link_group_id: group_id,
          format: week[:format]
        }.merge(target_range_for(week))
      )

      # Built directly on the association rather than through
      # scoring_slots_attributes=, which — via Tournament's own
      # reject_if: ->(attrs) { attrs["species_id"].blank? } — would silently
      # drop a blank species_id instead of surfacing it as a validation
      # failure. accepts_nested_attributes_for already switched the
      # association's autosave on, so a slot built here is still validated
      # and saved alongside the tournament.
      tournament.scoring_slots.build(species_id: week[:species_id], slot_count: week[:slot_count] || 1)
      tournament
    end

    # target_min_inches/target_max_inches are NOT NULL columns with model
    # defaults (70/100) that only apply when the attribute is left unset —
    # passing an explicit nil overrides the default and trips the DB's NOT NULL
    # constraint on save, which is a 500 rather than a validation failure.
    #
    # Key-presence alone is NOT enough to gate on: the scheduler's range inputs
    # are HIDDEN with a CSS class, not removed, so they submit on every format.
    # Pick Random Bag, clear "Target min", switch back to Standard and submit,
    # and this hash arrives carrying target_min_inches => "" — which casts to
    # nil, and random_bag_range_valid (the validation that would otherwise
    # catch it) returns early because the format isn't Random Bag any more.
    # Only Random Bag can set these at all; every other format keeps the
    # column defaults untouched. A blank one on an actual Random Bag week is
    # still sent, so it surfaces as "needs a target range" rather than
    # silently becoming 70.
    RANGE_FORMAT = "random_bag".freeze

    def target_range_for(week)
      return {} unless week[:format].to_s == RANGE_FORMAT
      range = {}
      range[:target_min_inches] = week[:target_min_inches] if week.key?(:target_min_inches)
      range[:target_max_inches] = week[:target_max_inches] if week.key?(:target_max_inches)
      range
    end
  end
end
