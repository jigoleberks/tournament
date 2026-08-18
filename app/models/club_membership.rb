class ClubMembership < ApplicationRecord
  belongs_to :user
  belongs_to :club

  enum :role, { member: 0, organizer: 1 }

  validates :user_id, uniqueness: { scope: :club_id }

  scope :active, -> { where(deactivated_at: nil) }

  # A membership whose USER is also active. `club_memberships.deactivated_at`
  # is vestigial — nothing in the app ever writes it; deactivating a member
  # sets `users.deactivated_at` (Admin::MembersController#destroy,
  # Organizers::MembersController#destroy). So `active` on its own degenerates
  # to "is a member of this club at all" and happily admits departed anglers.
  #
  # Any check about *another* user's standing — a boat's captain, last week's
  # crew — must use this scope. `active` alone is only safe for the signed-in
  # user, whom Authentication#current_user already rejects when deactivated.
  scope :with_active_user, -> { active.joins(:user).merge(User.active) }

  def deactivated?
    deactivated_at.present?
  end
end
