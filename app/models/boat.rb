class Boat < ApplicationRecord
  belongs_to :club
  belongs_to :captain, class_name: "User", foreign_key: :captain_user_id
  has_many :tournament_entries, dependent: :nullify

  scope :active, -> { where(active: true) }
  scope :alphabetical, -> { order(Arel.sql("lower(name)")) }

  before_validation :strip_name
  validates :name, presence: true
  validate :name_unique_in_club
  validate :captain_is_an_active_club_member

  # "Majestic Red — Kurtis Sanguin". Single source of the row label so the
  # picker, the setup screen, and the entry list can't drift apart.
  def label
    "#{name} — #{captain.name.strip}"
  end

  private

  def strip_name
    self.name = name.to_s.strip
  end

  def name_unique_in_club
    return if club_id.nil? || name.blank?
    clash = Boat.where(club_id: club_id)
                .where("lower(name) = ?", name.downcase)
                .where.not(id: id)
                .exists?
    errors.add(:name, "is already a boat in this club") if clash
  end

  # Enforced only when the captain is being set or changed. A boat whose
  # captain has since left the club stays valid, so an organizer can still fix
  # a typo in its name without being forced to reassign it first — and so the
  # captain picker (which keeps the departed captain as the selected option,
  # see BoatsHelper#boat_captain_options) can save unchanged.
  #
  # with_active_user, not active: see ClubMembership for why the membership's
  # own deactivated_at can't be trusted on its own.
  def captain_is_an_active_club_member
    return if club_id.nil? || captain_user_id.nil?
    return unless new_record? || captain_user_id_changed?
    member = ClubMembership.with_active_user.exists?(club_id: club_id, user_id: captain_user_id)
    errors.add(:captain, "must be an active member of this club") unless member
  end
end
