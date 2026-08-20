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
  def season_points_ladders_text=(values)
    parsed = Array(values).map { |v| parse_points_list(v) }
    @season_points_ladders_invalid = parsed.any?(&:nil?)
    self.season_points_ladders = parsed.compact
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

  def season_points_ladder_text(index)
    Array(season_points_ladders[index]).map { |n| format_points_amount(n) }.join(", ")
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
    return if multipliers.all? { |m| m.to_f.positive? }
    errors.add(:season_points_tier_multipliers, "must all be greater than zero")
  end

  def validate_ladder(ladder, attribute)
    unless ladder.is_a?(Array) && ladder.any?
      errors.add(attribute, "needs at least one place")
      return
    end
    if ladder.any? { |amount| amount.to_f.negative? }
      errors.add(attribute, "can't include negative amounts")
    end
    return if ladder.each_cons(2).all? { |a, b| a.to_f >= b.to_f }
    errors.add(attribute, "must be listed highest first")
  end
end
