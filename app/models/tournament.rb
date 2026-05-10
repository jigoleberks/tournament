class Tournament < ApplicationRecord
  belongs_to :club
  has_many :scoring_slots, dependent: :destroy
  accepts_nested_attributes_for :scoring_slots, allow_destroy: true,
                                reject_if: ->(attrs) { attrs["species_id"].blank? }
  has_many :tournament_entries, dependent: :destroy
  has_many :tournament_judges, dependent: :destroy
  has_many :catch_placements, dependent: :destroy
  has_many :judge_users, through: :tournament_judges, source: :user
  enum :kind, { event: 0, ongoing: 1 }
  enum :mode, { solo: 0, team: 1 }, prefix: true
  enum :format, { standard: 0, big_fish_season: 1, hidden_length: 2, biggest_vs_smallest: 3, fish_train: 4 }, prefix: true

  validates :name, :kind, :mode, :starts_at, presence: true
  validate :blind_leaderboard_requires_end_time
  validate :blind_leaderboard_locked_after_start, on: :update
  validate :format_locked_after_start, on: :update
  validate :big_fish_season_requires_solo
  validate :big_fish_season_requires_one_scoring_slot
  validate :hidden_length_requires_one_scoring_slot
  validate :hidden_length_requires_event_kind_with_end_time
  validate :hidden_length_target_locked_once_set
  validate :hidden_length_target_in_range
  validate :biggest_vs_smallest_requires_one_scoring_slot
  validate :biggest_vs_smallest_requires_event_kind_with_end_time
  validate :fish_train_requires_event_kind_with_end_time
  validate :fish_train_pool_size_between_1_and_3
  validate :fish_train_train_cars_length_between_3_and_6
  validate :fish_train_train_cars_species_in_pool

  scope :active_at, ->(time) {
    where("starts_at <= ?", time).where("ends_at IS NULL OR ends_at >= ?", time)
  }

  def active?(at: Time.current)
    starts_at <= at && (ends_at.nil? || ends_at >= at)
  end

  def started?(at: Time.current)
    starts_at.present? && starts_at <= at
  end

  def ended?(at: Time.current)
    ends_at.present? && ends_at < at
  end

  def blind?(at: Time.current)
    blind_leaderboard? && active?(at: at)
  end

  def friendly?
    !judged?
  end

  after_save :schedule_lifecycle_jobs

  private

  def schedule_lifecycle_jobs
    if saved_change_to_starts_at? && starts_at.future?
      TournamentLifecycleAnnounceJob.set(wait_until: starts_at).perform_later(tournament_id: id, kind: "started")
    end
    if saved_change_to_ends_at? && ends_at&.future?
      TournamentLifecycleAnnounceJob.set(wait_until: ends_at).perform_later(tournament_id: id, kind: "ended")
    end
  end

  def big_fish_season_requires_solo
    return unless format_big_fish_season?
    return if mode_solo?
    errors.add(:format, "Big Fish Season tournaments must be solo")
  end

  def big_fish_season_requires_one_scoring_slot
    return unless format_big_fish_season?
    remaining = scoring_slots.reject(&:marked_for_destruction?)
    return if remaining.size == 1
    errors.add(:scoring_slots, "Big Fish Season tournaments must have exactly one species configured")
  end

  def hidden_length_requires_one_scoring_slot
    return unless format_hidden_length?
    remaining = scoring_slots.reject(&:marked_for_destruction?)
    return if remaining.size == 1
    errors.add(:scoring_slots, "Hidden Length tournaments must have exactly one species configured")
  end

  def hidden_length_requires_event_kind_with_end_time
    return unless format_hidden_length?
    return if event? && ends_at.present?
    errors.add(:format, "Hidden Length tournaments must be event kind with an end time")
  end

  def biggest_vs_smallest_requires_one_scoring_slot
    return unless format_biggest_vs_smallest?
    remaining = scoring_slots.reject(&:marked_for_destruction?)
    return if remaining.size == 1
    errors.add(:scoring_slots, "Biggest vs Smallest tournaments must have exactly one species configured")
  end

  def biggest_vs_smallest_requires_event_kind_with_end_time
    return unless format_biggest_vs_smallest?
    return if event? && ends_at.present?
    errors.add(:format, "Biggest vs Smallest tournaments must be event kind with an end time")
  end

  def hidden_length_target_locked_once_set
    # "Locked" means once non-nil, the value can't be changed *or* cleared back to nil.
    return unless will_save_change_to_hidden_length_target?
    return if hidden_length_target_was.nil?
    errors.add(:hidden_length_target, "can't be changed once set")
  end

  def hidden_length_target_in_range
    return unless format_hidden_length?
    return if hidden_length_target.blank?
    target = hidden_length_target.to_d
    in_bounds = target >= "12.00".to_d && target <= "22.00".to_d
    on_quarter = (target * 4) == (target * 4).truncate
    return if in_bounds && on_quarter
    errors.add(:hidden_length_target, "must be a quarter-inch step between 12.00 and 22.00")
  end

  def blind_leaderboard_requires_end_time
    return unless blind_leaderboard?
    if ends_at.blank? || ongoing?
      errors.add(:blind_leaderboard, "requires an end time")
    end
  end

  def blind_leaderboard_locked_after_start
    return unless will_save_change_to_blind_leaderboard?
    return if starts_at.blank? || starts_at > Time.current
    errors.add(:blind_leaderboard, "can't be changed once the tournament has started")
  end

  def format_locked_after_start
    return unless will_save_change_to_format?
    return if starts_at.blank? || starts_at > Time.current
    errors.add(:format, "can't be changed once the tournament has started")
  end

  def fish_train_requires_event_kind_with_end_time
    return unless format_fish_train?
    return if event? && ends_at.present?
    errors.add(:format, "Fish Train tournaments must be event kind with an end time")
  end

  def fish_train_pool_size_between_1_and_3
    return unless format_fish_train?
    remaining = scoring_slots.reject(&:marked_for_destruction?)
    distinct_count = remaining.map(&:species_id).uniq.size
    return if distinct_count.between?(1, 3)
    errors.add(:scoring_slots, "Fish Train tournaments must have between 1 and 3 species in the pool")
  end

  def fish_train_train_cars_length_between_3_and_6
    return unless format_fish_train?
    size = (train_cars || []).size
    return if size.between?(3, 6)
    errors.add(:train_cars, "Fish Train must have between 3 and 6 cars")
  end

  def fish_train_train_cars_species_in_pool
    return unless format_fish_train?
    remaining = scoring_slots.reject(&:marked_for_destruction?)
    pool_species_ids = remaining.map(&:species_id).compact.uniq
    cars = train_cars || []
    return if cars.empty?
    return if cars.all? { |sp_id| pool_species_ids.include?(sp_id) }
    errors.add(:train_cars, "Fish Train cars must reference species in the pool")
  end
end
