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

  validates :name, :kind, :mode, :starts_at, presence: true

  scope :active_at, ->(time) {
    where("starts_at <= ?", time).where("ends_at IS NULL OR ends_at >= ?", time)
  }

  def active?(at: Time.current)
    starts_at <= at && (ends_at.nil? || ends_at >= at)
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
end
