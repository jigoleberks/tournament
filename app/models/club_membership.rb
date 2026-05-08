class ClubMembership < ApplicationRecord
  belongs_to :user
  belongs_to :club

  enum :role, { member: 0, organizer: 1 }

  validates :user_id, uniqueness: { scope: :club_id }

  scope :active, -> { where(deactivated_at: nil) }

  def deactivated?
    deactivated_at.present?
  end
end
