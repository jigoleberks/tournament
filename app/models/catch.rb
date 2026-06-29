class Catch < ApplicationRecord
  self.table_name = "catches"
  belongs_to :user
  belongs_to :species
  belongs_to :logged_by_user, class_name: "User", optional: true
  has_one_attached :photo
  has_one_attached :reference_photo       # admin-added photo that supersedes the original for display
  has_one_attached :video                 # not used in Phase 1; reserved for Phase 2
  has_many :catch_placements, dependent: :destroy
  has_many :judge_actions, dependent: :destroy

  # The photo shown to viewers. An admin-added reference photo supersedes the
  # angler's original submission for display; the original stays visible to
  # staff on the judge review page.
  def display_photo
    reference_photo.attached? ? reference_photo : photo
  end

  enum :status, {
    pending_sync: 0,
    synced:       1,
    needs_review: 2,
    disputed:     3,
    disqualified: 4
  }

  # Hard upper bounds (inches) per species, to catch fat-finger length entries.
  # Keyed by downcased species name. Species not listed are unbounded.
  MAX_LENGTH_BY_SPECIES = {
    "perch" => 20, "walleye" => 50, "pike" => 70, "bass" => 35,
    "lake trout" => 55, "stocked trout" => 35, "tagged walleye" => 50,
    "other" => 200
  }.freeze
  PHOTO_CONTENT_TYPES = %w[image/jpeg image/png image/heic image/heif image/webp].freeze
  # Native full-res phone cameras can produce 100+ MP stills; a single
  # high-res shot can reach ~20 MB, and a 200 MP sensor more. 50 MB leaves
  # headroom so a legitimate full-resolution catch photo is never rejected.
  PHOTO_MAX_BYTES = 50.megabytes

  validates :length_inches, numericality: { greater_than: 0 }
  validates :length_unit, inclusion: { in: %w[inches centimeters] }
  validates :captured_at_device, presence: true
  validates :client_uuid, presence: true, uniqueness: true
  validate :photo_must_be_attached
  validate :photo_within_limits
  validate :reference_photo_within_limits
  validate :length_within_species_cap
  validates :note, length: { maximum: 500 }, allow_blank: true

  TAG_NUMBER_FORMAT = /\A[A-Z0-9-]+\z/.freeze

  before_validation :normalize_tag_number
  before_validation :default_length_unit
  validate :tag_number_required_for_tagged_walleye
  validates :tag_number,
            format: { with: TAG_NUMBER_FORMAT, message: "may only contain letters, numbers, and dashes" },
            length: { maximum: 16 },
            allow_blank: true

  before_validation :normalize_weight_text
  validates :weight_text, length: { maximum: 32 }, allow_blank: true

  def latest_approver
    # max_by walks the in-memory array so an eager-loaded :judge_actions stays
    # consumed; .order(:created_at).last would re-query Postgres per row and
    # defeat Leaderboards::Build's includes(:judge_actions => :judge_user).
    last = judge_actions.max_by(&:created_at)
    last&.approve? ? last.judge_user : nil
  end

  def disqualification_note
    return nil unless disqualified?
    # Walk the in-memory association (like latest_approver) so an eager-loaded
    # :judge_actions stays consumed instead of re-querying Postgres per row.
    # Tie-break on id so two disqualifies at the same created_at are
    # deterministic (latest timestamp, then highest id = most recently created).
    judge_actions.select(&:disqualify?).max_by { |a| [a.created_at, a.id] }&.note
  end

  private

  def normalize_tag_number
    self.tag_number = tag_number.to_s.strip.upcase if tag_number.present?
  end

  def default_length_unit
    return if length_unit.present?
    self.length_unit = Catches::InferLoggedUnit.call(
      length_inches: length_inches,
      user_length_unit: user&.length_unit
    )
  end

  def normalize_weight_text
    trimmed = weight_text.to_s.strip
    self.weight_text = trimmed.presence
  end

  def tag_number_required_for_tagged_walleye
    return if species.nil?
    return unless species.tagged_walleye?
    return if tag_number.present?
    errors.add(:tag_number, "is required for Tagged Walleye catches")
  end

  def photo_must_be_attached
    errors.add(:photo, "is required") unless photo.attached?
  end

  def photo_within_limits
    attachment_within_limits(photo, :photo)
  end

  # An admin-uploaded reference photo supersedes the original as display_photo for
  # every viewer and is run through libvips variants on render, so it needs the
  # same content-type/size gate as the original — the form's accept= is
  # client-side only and a non-image would 500 the catch list/detail pages.
  def reference_photo_within_limits
    attachment_within_limits(reference_photo, :reference_photo)
  end

  # Shared content-type/size gate for both the original and reference photo.
  def attachment_within_limits(attachment, field)
    return unless attachment.attached?
    unless PHOTO_CONTENT_TYPES.include?(attachment.content_type)
      errors.add(field, "must be a JPEG, PNG, HEIC, or WebP image")
    end
    if attachment.byte_size.to_i > PHOTO_MAX_BYTES
      errors.add(field, "is larger than #{PHOTO_MAX_BYTES / 1.megabyte}MB")
    end
  end

  # Max length (inches) for a species, or nil if the species is unbounded.
  # Single source of truth for the cap lookup (validation, controller, views).
  def self.length_cap_for(species)
    return nil if species.nil?
    MAX_LENGTH_BY_SPECIES[species.name.to_s.downcase]
  end

  def length_within_species_cap
    return if species.nil? || length_inches.nil?
    cap = Catch.length_cap_for(species)
    return if cap.nil? || length_inches <= cap
    errors.add(:length_inches, "for #{species.name} can't exceed #{cap}\"")
  end
end
