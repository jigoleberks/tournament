class TournamentTemplate < ApplicationRecord
  belongs_to :club
  has_many :tournament_template_scoring_slots, dependent: :destroy
  accepts_nested_attributes_for :tournament_template_scoring_slots, allow_destroy: true,
                                reject_if: ->(attrs) { attrs["species_id"].blank? }
  enum :mode, { solo: 0, team: 1 }, prefix: true
  enum :format, { standard: 0, big_fish_season: 1, hidden_length: 2, biggest_vs_smallest: 3 }, prefix: true
  validates :name, presence: true
  validates :default_weekday, inclusion: { in: 0..6 }, allow_nil: true
  validate :default_schedule_all_or_nothing
  validate :default_end_after_default_start
  validate :big_fish_season_requires_solo
  validate :big_fish_season_requires_one_scoring_slot
  validate :hidden_length_requires_one_scoring_slot
  validate :biggest_vs_smallest_requires_one_scoring_slot

  def scheduled?
    default_weekday.present? && default_start_time.present? && default_end_time.present?
  end

  def next_occurrence_at(now: Time.zone.now)
    return nil unless scheduled?
    today = now.to_date
    days_ahead = (default_weekday - today.wday) % 7
    candidate_date = today + days_ahead.days
    starts = combine(candidate_date, default_start_time)
    starts += 7.days if days_ahead.zero? && starts <= now
    ends = combine(starts.to_date, default_end_time)
    [starts, ends]
  end

  def default_schedule_summary
    return nil unless scheduled?
    "#{Date::DAYNAMES[default_weekday]} #{default_start_time.strftime("%-l:%M %p")}–#{default_end_time.strftime("%-l:%M %p")}"
  end

  private

  def combine(date, time)
    Time.zone.local(date.year, date.month, date.day, time.hour, time.min, time.sec)
  end

  def default_schedule_all_or_nothing
    fields = [default_weekday, default_start_time, default_end_time]
    return if fields.all?(&:blank?) || fields.all?(&:present?)
    errors.add(:base, "weekday, start time, and end time must all be set together (or all left blank)")
  end

  def default_end_after_default_start
    return unless default_start_time.present? && default_end_time.present?
    return if default_end_time > default_start_time
    errors.add(:default_end_time, "must be after the start time")
  end

  def big_fish_season_requires_solo
    return unless format_big_fish_season?
    return if mode_solo?
    errors.add(:format, "Big Fish Season tournaments must be solo")
  end

  def big_fish_season_requires_one_scoring_slot
    return unless format_big_fish_season?
    remaining = tournament_template_scoring_slots.reject(&:marked_for_destruction?)
    return if remaining.size == 1
    errors.add(:tournament_template_scoring_slots,
               "Big Fish Season tournaments must have exactly one species configured")
  end

  def hidden_length_requires_one_scoring_slot
    return unless format_hidden_length?
    remaining = tournament_template_scoring_slots.reject(&:marked_for_destruction?)
    return if remaining.size == 1
    errors.add(:tournament_template_scoring_slots,
               "Hidden Length tournaments must have exactly one species configured")
  end

  def biggest_vs_smallest_requires_one_scoring_slot
    return unless format_biggest_vs_smallest?
    remaining = tournament_template_scoring_slots.reject(&:marked_for_destruction?)
    return if remaining.size == 1
    errors.add(:tournament_template_scoring_slots,
               "Biggest vs Smallest tournaments must have exactly one species configured")
  end
end
