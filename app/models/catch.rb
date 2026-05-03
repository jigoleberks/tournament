class Catch < ApplicationRecord
  self.table_name = "catches"
  belongs_to :user
  belongs_to :species
  has_one_attached :photo
  has_one_attached :video                 # not used in Phase 1; reserved for Phase 2
  has_many :catch_placements, dependent: :destroy
  has_many :judge_actions, dependent: :destroy

  enum :status, {
    pending_sync: 0,
    synced:       1,
    needs_review: 2,
    disputed:     3,
    disqualified: 4
  }

  MAX_LENGTH_BY_SPECIES = { "perch" => 20, "walleye" => 50, "pike" => 70 }.freeze

  validates :length_inches, numericality: { greater_than: 0 }
  validates :captured_at_device, presence: true
  validates :client_uuid, presence: true, uniqueness: true
  validate :photo_must_be_attached
  validate :length_within_species_cap
  validates :note, length: { maximum: 500 }, allow_blank: true

  def latest_approver
    last = judge_actions.order(:created_at).last
    last&.approve? ? last.judge_user : nil
  end

  def disqualification_note
    return nil unless disqualified?
    judge_actions.where(action: :disqualify).order(:created_at).last&.note
  end

  private

  def photo_must_be_attached
    errors.add(:photo, "is required") unless photo.attached?
  end

  def length_within_species_cap
    return if species.nil? || length_inches.nil?
    cap = MAX_LENGTH_BY_SPECIES[species.name.to_s.downcase]
    return if cap.nil? || length_inches <= cap
    errors.add(:length_inches, "for #{species.name} can't exceed #{cap}\"")
  end
end
