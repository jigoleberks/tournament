class TournamentTemplate < ApplicationRecord
  belongs_to :club
  belongs_to :paired_template, class_name: "TournamentTemplate", optional: true
  has_many :tournament_template_scoring_slots, dependent: :destroy
  accepts_nested_attributes_for :tournament_template_scoring_slots, allow_destroy: true,
                                reject_if: ->(attrs) { attrs["species_id"].blank? }
  enum :mode, { solo: 0, team: 1 }, prefix: true
  enum :format, { standard: 0, big_fish_season: 1, hidden_length: 2, biggest_vs_smallest: 3, fish_train: 4, tagged: 5, smallest_fish: 6, pro_walleye: 7, progressive_length: 9, beat_the_average: 10 }, prefix: true
  validates :name, presence: true
  validates :default_weekday, inclusion: { in: 0..6 }, allow_nil: true
  validate :default_schedule_all_or_nothing
  validate :default_end_after_default_start
  validate :big_fish_season_requires_solo
  validate :big_fish_season_requires_one_scoring_slot
  validate :hidden_length_requires_one_scoring_slot
  validate :biggest_vs_smallest_requires_one_scoring_slot
  validate :fish_train_pool_size_between_1_and_3
  validate :fish_train_train_cars_length_between_3_and_6
  validate :fish_train_train_cars_species_in_pool
  validate :tagged_requires_solo
  validate :tagged_requires_one_tagged_walleye_scoring_slot
  validate :pro_walleye_requires_one_walleye_scoring_slot
  before_validation :force_pro_walleye_slot_count
  validate :progressive_length_requires_one_scoring_slot
  validate :paired_template_cannot_be_self
  validate :paired_template_must_be_same_club
  validate :paired_template_must_be_available
  after_save :sync_pairing

  def paired?
    paired_template_id.present?
  end

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

  def fish_train_pool_size_between_1_and_3
    return unless format_fish_train?
    remaining = tournament_template_scoring_slots.reject(&:marked_for_destruction?)
    distinct_count = remaining.map(&:species_id).uniq.size
    return if distinct_count.between?(1, 3)
    errors.add(:tournament_template_scoring_slots,
               "Fish Train tournaments must have between 1 and 3 species in the pool")
  end

  def fish_train_train_cars_length_between_3_and_6
    return unless format_fish_train?
    size = (train_cars || []).size
    return if size.between?(3, 6)
    errors.add(:train_cars, "Fish Train must have between 3 and 6 cars")
  end

  def fish_train_train_cars_species_in_pool
    return unless format_fish_train?
    remaining = tournament_template_scoring_slots.reject(&:marked_for_destruction?)
    pool_species_ids = remaining.map(&:species_id).compact.uniq
    cars = train_cars || []
    return if cars.empty?
    return if cars.all? { |sp_id| pool_species_ids.include?(sp_id) }
    errors.add(:train_cars, "Fish Train cars must reference species in the pool")
  end

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

  def tagged_requires_solo
    return unless format_tagged?
    return if mode_solo?
    errors.add(:format, "Tagged Walleye tournaments must be solo")
  end

  def tagged_requires_one_tagged_walleye_scoring_slot
    return unless format_tagged?
    remaining = tournament_template_scoring_slots.reject(&:marked_for_destruction?)
    unless remaining.size == 1 && remaining.first.species&.tagged_walleye?
      errors.add(:tournament_template_scoring_slots,
                 "Tagged Walleye tournaments must have exactly one scoring slot for the Tagged Walleye species")
    end
  end

  def pro_walleye_requires_one_walleye_scoring_slot
    return unless format_pro_walleye?
    remaining = tournament_template_scoring_slots.reject(&:marked_for_destruction?)
    unless remaining.size == 1 && remaining.first.species&.walleye?
      errors.add(:tournament_template_scoring_slots,
                 "Pro Walleye tournaments must have exactly one scoring slot for the Walleye species")
    end
  end

  # The basket is a fixed 5 fish, so pin the slot's count to the basket size (the
  # slot-count field is "ignored" in the UI). Mirrors Tournament#force_pro_walleye_slot_count
  # so a template stores the same capacity a cloned tournament will.
  def force_pro_walleye_slot_count
    return unless format_pro_walleye?
    tournament_template_scoring_slots.reject(&:marked_for_destruction?).each do |s|
      s.slot_count = Catches::ProWalleye::BASKET_SIZE
    end
  end

  def progressive_length_requires_one_scoring_slot
    return unless format_progressive_length?
    remaining = tournament_template_scoring_slots.reject(&:marked_for_destruction?)
    return if remaining.size == 1
    errors.add(:tournament_template_scoring_slots,
               "Progressive Length tournaments must have exactly one species configured")
  end

  def paired_template_cannot_be_self
    return if paired_template_id.blank?
    return unless paired_template_id == id
    errors.add(:paired_template, "can't be the same template")
  end

  def paired_template_must_be_same_club
    return if paired_template.nil?
    return if paired_template.club_id == club_id
    errors.add(:paired_template, "must belong to the same club")
  end

  # A league night is exactly two templates, so a partner already spoken for
  # can't be taken. Without this, pairing C to B would silently orphan A.
  #
  # Reads the partner's current pairing straight from the DB rather than off
  # `paired_template` — an in-memory association object can be a stale copy
  # (e.g. loaded before another template's `sync_pairing` repointed it via
  # `update_column`, which never touches Ruby objects held elsewhere).
  def paired_template_must_be_available
    return if paired_template.nil?
    current_partner_id = TournamentTemplate.where(id: paired_template_id).pick(:paired_template_id)
    return if current_partner_id.nil?
    return if current_partner_id == id
    errors.add(:paired_template, "is already paired with another template")
  end

  # Pairing is symmetric: whichever side you set it from, both rows end up
  # pointing at each other. The guard stops the partner's own after_save from
  # bouncing the update back.
  def sync_pairing
    return if @syncing_pairing
    return unless saved_change_to_paired_template_id?

    previous_id, current_id = saved_change_to_paired_template_id
    @syncing_pairing = true

    if previous_id
      former = TournamentTemplate.find_by(id: previous_id)
      former&.update_column(:paired_template_id, nil)
    end
    if current_id
      partner = TournamentTemplate.find_by(id: current_id)
      partner&.update_column(:paired_template_id, id)
    end
  ensure
    @syncing_pairing = false
  end
end
