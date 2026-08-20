class Club < ApplicationRecord
  has_many :club_memberships, dependent: :destroy
  has_many :members, through: :club_memberships, source: :user
  has_many :tournaments, dependent: :destroy
  has_many :boats, dependent: :destroy
  has_many :tournament_templates, dependent: :destroy
  has_many :rules_revisions, class_name: "ClubRulesRevision", dependent: :destroy
  enum :active_rules_season, { open_water: 0, ice: 1 }, prefix: true
  enum :banner_style, { info: 0, good: 1, alert: 2 }, default: :info

  enum :season_points_scheme,
       { tiered_ladders: 0, base_ladder: 1, full_field: 2 },
       prefix: :season_points_scheme,
       default: :tiered_ladders

  # Fixed field-size bands, by entry (boat/team) count. The last band is
  # open-ended so a big night can't fall through a hole.
  SEASON_POINTS_BANDS = [1..9, 10..19, 20..29, 30..Float::INFINITY].freeze

  # Single source of truth for the band labels and a representative sample
  # field size, derived from SEASON_POINTS_BANDS. Used by the admin editor
  # (labels + preview table) and the member-facing "how points work"
  # explainer so all three can't drift out of sync with each other or with
  # the bands themselves. The sample is the TOP of each band (the open-ended
  # last band uses its lower bound instead) — not a mid-band number — so a
  # raised season_points_min_entries can't make a band that genuinely does
  # pay placement points look like it never pays.
  def self.season_points_bands
    SEASON_POINTS_BANDS.map do |band|
      if band.end == Float::INFINITY
        { label: "#{band.begin}+", sample: band.begin }
      else
        { label: "#{band.begin}–#{band.end}", sample: band.end }
      end
    end
  end

  validates :name, presence: true, uniqueness: true
  validate :season_points_ladders_are_well_formed
  validate :season_points_base_ladder_is_well_formed
  validate :season_points_tier_multipliers_are_well_formed
  validates :season_points_attendance,
            numericality: { greater_than_or_equal_to: 0 }
  validates :season_points_min_entries,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  def current_rules_revision
    ClubRulesRevision.latest_for(club: self, season: active_rules_season)
  end

  # Comma-separated form input ("9, 6, 3") → the jsonb arrays. parse_points_list
  # returns nil when any token isn't a number, and each writer flags only its
  # OWN attribute — so junk in the base ladder doesn't put an error on the
  # tiered ladders too.
  #
  # The four submitted strings are positional (one per SEASON_POINTS_BANDS
  # entry) and must stay that way. `compact`-ing out a band that failed to
  # parse used to shift every later band down one slot — on 422 the form
  # would silently re-render band 3's ladder under band 2's label, and if the
  # admin then "fixed" what they saw and resubmitted, it would save a ladder
  # against the wrong band with no error at all. So: never reassign
  # season_points_ladders when any band is invalid (the record is already
  # marked invalid via @season_points_ladders_invalid), and stash the raw
  # submitted strings so the re-rendered form echoes exactly what was typed,
  # in place, including the offending band.
  def season_points_ladders_text=(values)
    @season_points_ladders_text = Array(values).map(&:to_s)
    parsed = @season_points_ladders_text.map { |v| parse_points_list(v) }
    @season_points_ladders_invalid = parsed.any?(&:nil?)
    self.season_points_ladders = parsed unless @season_points_ladders_invalid
  end

  def season_points_base_ladder_text=(value)
    parsed = parse_points_list(value)
    @season_points_base_ladder_invalid = parsed.nil?
    self.season_points_base_ladder = parsed || []
  end

  def season_points_tier_multipliers_text=(value)
    parsed = parse_points_list(value)
    @season_points_tier_multipliers_invalid = parsed.nil?
    self.season_points_tier_multipliers = parsed || []
  end

  # Prefers the raw text just submitted via season_points_ladders_text= (so a
  # 422 re-render shows the admin exactly what they typed, band-for-band,
  # even for a band that failed to parse) and falls back to formatting the
  # persisted value when the writer hasn't run this request (a plain GET).
  def season_points_ladder_text(index)
    if @season_points_ladders_text
      @season_points_ladders_text[index].to_s
    else
      Array(season_points_ladders[index]).map { |n| format_points_amount(n) }.join(", ")
    end
  end

  def season_points_base_ladder_text
    Array(season_points_base_ladder).map { |n| format_points_amount(n) }.join(", ")
  end

  def season_points_tier_multipliers_text
    Array(season_points_tier_multipliers).map { |n| format_points_amount(n) }.join(", ")
  end

  private

  # Ladders are stored as floats once they pass through a _text= writer
  # (parse_points_list maps every token to_f), so a whole number like 10
  # would otherwise render back into the form as "10.0". Strip the trailing
  # ".0" so the field round-trips the way the user typed it.
  def format_points_amount(amount)
    value = amount.to_f
    value == value.to_i ? value.to_i.to_s : value.to_s
  end

  # nil means "at least one token wasn't a number" — the caller decides which
  # attribute to hang the error on.
  def parse_points_list(value)
    tokens = value.to_s.split(",").map(&:strip)
    return nil if tokens.empty? || tokens.any? { |t| !t.match?(/\A\d+(\.\d+)?\z/) }
    tokens.map(&:to_f)
  end

  def season_points_ladders_are_well_formed
    if @season_points_ladders_invalid
      errors.add(:season_points_ladders, "must be numbers separated by commas")
      return
    end
    ladders = season_points_ladders
    unless ladders.is_a?(Array) && ladders.size == SEASON_POINTS_BANDS.size
      errors.add(:season_points_ladders, "needs one ladder per field-size band")
      return
    end
    ladders.each { |ladder| validate_ladder(ladder, :season_points_ladders) }
  end

  def season_points_base_ladder_is_well_formed
    if @season_points_base_ladder_invalid
      errors.add(:season_points_base_ladder, "must be numbers separated by commas")
      return
    end
    validate_ladder(season_points_base_ladder, :season_points_base_ladder)
  end

  def season_points_tier_multipliers_are_well_formed
    if @season_points_tier_multipliers_invalid
      errors.add(:season_points_tier_multipliers, "must be numbers separated by commas")
      return
    end
    multipliers = season_points_tier_multipliers
    unless multipliers.is_a?(Array) && multipliers.size == SEASON_POINTS_BANDS.size
      errors.add(:season_points_tier_multipliers, "needs one multiplier per field-size band")
      return
    end
    unless multipliers.all? { |m| m.is_a?(Numeric) }
      errors.add(:season_points_tier_multipliers, "must be numbers")
      return
    end
    return if multipliers.all?(&:positive?)
    errors.add(:season_points_tier_multipliers, "must all be greater than zero")
  end

  # Requires actual Numeric entries rather than coercing with #to_f: a jsonb
  # column happily stores strings, and a club saved via update_column (or any
  # other path that skips these callbacks) can end up with a ladder like
  # ["9", "6", "3"]. That used to pass every check here (to_f coerces) and
  # only blow up downstream, as a TypeError, the first time
  # SeasonPointsAwarded tried to add a String to an accumulator — a 500 on a
  # member-facing page. Both the text writers (which produce Floats) and the
  # jsonb column defaults (Integers) satisfy Numeric, so legitimate data
  # stays valid.
  def validate_ladder(ladder, attribute)
    unless ladder.is_a?(Array) && ladder.any?
      errors.add(attribute, "needs at least one place")
      return
    end
    unless ladder.all? { |amount| amount.is_a?(Numeric) }
      errors.add(attribute, "must be numbers")
      return
    end
    if ladder.any?(&:negative?)
      errors.add(attribute, "can't include negative amounts")
    end
    return if ladder.each_cons(2).all? { |a, b| a >= b }
    errors.add(attribute, "must be listed highest first")
  end
end
