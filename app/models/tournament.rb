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
  enum :format, { standard: 0, big_fish_season: 1 }

  validates :name, :kind, :mode, :starts_at, presence: true
  validate :blind_leaderboard_requires_end_time
  validate :blind_leaderboard_locked_after_start, on: :update
  validate :big_fish_season_requires_solo

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
    return unless big_fish_season?
    return if mode_solo?
    errors.add(:format, "Big Fish Season tournaments must be solo")
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
end
