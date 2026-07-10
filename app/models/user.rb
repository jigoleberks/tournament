class User < ApplicationRecord
  has_many :club_memberships, dependent: :destroy
  has_many :clubs, through: :club_memberships
  has_many :tournament_entry_members, dependent: :destroy
  has_many :tournament_entries, through: :tournament_entry_members
  has_many :tournament_judges, dependent: :destroy
  has_many :tournament_deputies, dependent: :destroy
  # granted_by_user_id is NOT NULL, so :nullify isn't an option; destroy the
  # grants a purged user handed out rather than tripping the FK.
  has_many :granted_tournament_deputies, class_name: "TournamentDeputy",
           foreign_key: :granted_by_user_id, dependent: :destroy
  has_many :catches, dependent: :restrict_with_error
  has_many :push_subscriptions, dependent: :destroy
  has_many :judge_actions, foreign_key: :judge_user_id, dependent: :destroy
  has_many :user_events, dependent: :delete_all

  validates :name, :email, presence: true
  validates :email, uniqueness: { case_sensitive: false }

  # Normalize before validation so the case-insensitive uniqueness check and
  # the case-sensitive PG btree unique index agree. Without this, a race
  # between "Joe@x.com" and "joe@x.com" can pass validation independently and
  # both commit, leaving two rows the model thought were duplicates.
  before_validation :normalize_email
  def normalize_email
    self.email = email.to_s.strip.downcase if email.present?
  end

  scope :active, -> { where(deactivated_at: nil) }

  def deactivated?
    deactivated_at.present?
  end

  LENGTH_UNITS = %w[inches centimeters].freeze
  validates :length_unit, inclusion: { in: LENGTH_UNITS }

  LAST_SEEN_THROTTLE = 1.hour

  def metric?
    length_unit == "centimeters"
  end

  def touch_last_seen!
    return if last_seen_at && last_seen_at > LAST_SEEN_THROTTLE.ago
    update_columns(last_seen_at: Time.current)
  end

  # An active ClubMembership with role: :organizer. This is the *permanent*
  # role, and it is what gates privilege-granting actions (role changes,
  # deputy grants). `organizer_in?` is deliberately broader — see below.
  def permanent_organizer_in?(club)
    return false unless club
    club_memberships.active.where(club: club, role: :organizer).exists?
  end

  # The gate the whole app checks: both base controllers, the home-page nav,
  # CatchesHelper, Judges::BaseController and Leaderboards::ViewerScope. A
  # temporary deputy passes this, which is exactly why they also get the
  # organizer nav links for free.
  #
  # Memoized per club id because this is called several times per request
  # (three times in CatchesHelper alone) and the deputy fallback adds a second
  # query. A stable answer within one request is desirable anyway, given the
  # expiry is time-based.
  def organizer_in?(club)
    return false unless club
    @organizer_in ||= {}
    return @organizer_in[club.id] if @organizer_in.key?(club.id)
    @organizer_in[club.id] = permanent_organizer_in?(club) || active_deputy_in?(club)
  end

  # A live deputy grant: an active membership in the club, plus a grant on a
  # tournament of that club that has not started yet. Evaluated on read, so the
  # badge lapses at starts_at with no job and nothing to clean up.
  def active_deputy_in?(club)
    return false unless member_of?(club)
    TournamentDeputy.live.where(user_id: id, tournaments: { club_id: club.id }).exists?
  end

  def reload(*)
    @organizer_in = nil
    super
  end

  def member_of?(club)
    return false unless club
    club_memberships.active.where(club: club).exists?
  end

  def admin?
    !!admin
  end
end
