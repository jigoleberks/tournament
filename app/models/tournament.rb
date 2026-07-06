class Tournament < ApplicationRecord
  belongs_to :club
  belongs_to :drawn_winning_placement, class_name: "CatchPlacement", optional: true
  belongs_to :drawn_by_user,           class_name: "User",           optional: true
  has_many :scoring_slots, dependent: :destroy
  accepts_nested_attributes_for :scoring_slots, allow_destroy: true,
                                reject_if: ->(attrs) { attrs["species_id"].blank? }
  has_many :tournament_entries, dependent: :destroy
  has_many :tournament_judges, dependent: :destroy
  has_many :catch_placements, dependent: :destroy
  has_many :judge_users, through: :tournament_judges, source: :user
  enum :mode, { solo: 0, team: 1 }, prefix: true
  enum :format, { standard: 0, big_fish_season: 1, hidden_length: 2, biggest_vs_smallest: 3, fish_train: 4, tagged: 5, smallest_fish: 6, pro_walleye: 7, bingo: 8 }, prefix: true

  validates :name, :mode, :starts_at, :ends_at, presence: true
  validate :ends_at_after_starts_at
  validate :blind_leaderboard_locked_after_start, on: :update
  validate :format_locked_after_start, on: :update
  validate :train_cars_locked_after_start, on: :update
  validate :scoring_slots_locked_after_start, on: :update
  validate :big_fish_season_requires_solo
  validate :big_fish_season_requires_one_scoring_slot
  validate :hidden_length_requires_one_scoring_slot
  validate :hidden_length_target_locked_once_set
  validate :hidden_length_target_in_range
  validate :biggest_vs_smallest_requires_one_scoring_slot
  validate :fish_train_pool_size_between_1_and_3
  validate :fish_train_train_cars_length_between_3_and_6
  validate :fish_train_train_cars_species_in_pool
  validate :tagged_requires_solo
  validate :tagged_requires_one_tagged_walleye_scoring_slot
  validate :pro_walleye_requires_one_walleye_scoring_slot
  before_validation :force_pro_walleye_slot_count
  before_validation :assign_bingo_layout, on: :create
  validate :bingo_layout_well_formed
  validate :bingo_layout_locked_after_start, on: :update

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

  # Whether a judge's "force into slot index" manual override is meaningful here.
  # Only the slot-based top-N formats and append-only Fish Train have a durable,
  # positional slot_index. The length-derived formats (BvS / Smallest Fish / Pro
  # Walleye) re-derive the whole basket from length, and the every-catch formats
  # (Hidden Length / Tagged) place every catch — so a forced slot is meaningless
  # and would be silently reverted by the next reconcile.
  def supports_forced_slot?
    format_standard? || format_big_fish_season? || format_fish_train?
  end

  after_save :schedule_lifecycle_jobs

  private

  def ends_at_after_starts_at
    return if starts_at.blank? || ends_at.blank?
    return if ends_at > starts_at
    errors.add(:ends_at, "must be after the start time")
  end

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

  def biggest_vs_smallest_requires_one_scoring_slot
    return unless format_biggest_vs_smallest?
    remaining = scoring_slots.reject(&:marked_for_destruction?)
    return if remaining.size == 1
    errors.add(:scoring_slots, "Biggest vs Smallest tournaments must have exactly one species configured")
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

  def train_cars_locked_after_start
    return unless will_save_change_to_train_cars?
    return if starts_at.blank? || starts_at > Time.current
    errors.add(:train_cars, "can't be changed once the tournament has started")
  end

  # The species-and-quantity set is fixed once a tournament is active — the same
  # "no changes after start" rule as format/train_cars, applied to the scoring
  # slots. Blocks adding, removing, or editing a slot (species or slot_count).
  # This makes the "active tournaments never change" operating rule real in code,
  # and closes the mid-tournament slot-removal case that would otherwise strand
  # already-scored placements for a species the tournament no longer ranks. Same-
  # value reassignments (e.g. force_pro_walleye_slot_count pinning slot_count) are
  # not dirty, so a plain save of a started tournament still passes.
  def scoring_slots_locked_after_start
    return if starts_at.blank? || starts_at > Time.current
    return unless scoring_slots.any? { |s| s.new_record? || s.marked_for_destruction? || s.changed? }
    errors.add(:scoring_slots, "can't be changed once the tournament has started")
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

  def tagged_requires_solo
    return unless format_tagged?
    return if mode_solo?
    errors.add(:format, "Tagged Walleye tournaments must be solo")
  end

  def tagged_requires_one_tagged_walleye_scoring_slot
    return unless format_tagged?
    remaining = scoring_slots.reject(&:marked_for_destruction?)
    unless remaining.size == 1 && remaining.first.species&.tagged_walleye?
      errors.add(:scoring_slots,
                 "Tagged Walleye tournaments must have exactly one scoring slot for the Tagged Walleye species")
    end
  end

  def pro_walleye_requires_one_walleye_scoring_slot
    return unless format_pro_walleye?
    remaining = scoring_slots.reject(&:marked_for_destruction?)
    unless remaining.size == 1 && remaining.first.species&.walleye?
      errors.add(:scoring_slots,
                 "Pro Walleye tournaments must have exactly one scoring slot for the Walleye species")
    end
  end

  # The basket is a fixed 5 fish (at most 2 over 55 cm). PlaceInSlots/
  # ReconcileProWalleye enforce the basket size and over-cap themselves, but the
  # leaderboard `complete` flag and the winners/season-points capacity math read
  # scoring_slots.sum(:slot_count) — so pin the single slot to the basket size
  # here (the slot-count field is "ignored" in the UI).
  def force_pro_walleye_slot_count
    return unless format_pro_walleye?
    scoring_slots.reject(&:marked_for_destruction?).each { |s| s.slot_count = Catches::ProWalleye::BASKET_SIZE }
  end

  def assign_bingo_layout
    return unless format_bingo?
    return if bingo_layout.present?
    self.bingo_layout = Catches::Bingo::Tasks.random_layout
  end

  def bingo_layout_well_formed
    return unless format_bingo?
    layout = bingo_layout
    unless layout.is_a?(Array) && layout.size == 25 &&
           layout[Catches::Bingo::Tasks::FREE_INDEX] == "free" &&
           (layout - ["free"]).sort == Catches::Bingo::Tasks.keys.sort
      errors.add(:bingo_layout, "must be the 24 bingo tasks plus the free center cell")
    end
  end

  # Mirror scoring_slots_locked_after_start: the shuffled card freezes at start.
  def bingo_layout_locked_after_start
    return unless format_bingo?
    return unless will_save_change_to_bingo_layout?
    return if starts_at.blank? || starts_at > Time.current
    errors.add(:bingo_layout, "can't be changed once the tournament has started")
  end
end
