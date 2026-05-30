class Bait < ApplicationRecord
  belongs_to :user
  has_many :catches, dependent: :restrict_with_error

  scope :active,   -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  ATTR_MAX_LEN = 64
  validates :color, :weight, :lure_type, :bait_type,
            length: { maximum: ATTR_MAX_LEN }, allow_blank: true
  validate :at_least_one_attribute_present

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  # Examples from the user:
  #   "3/8 oz orange fireball + minnow"
  #   "1/2 oz blue/pink fireball + jumbo minnow"
  #   "1/4 oz white jighead + white curly tail plastic"
  def display_name
    parts = [weight, color, lure_type].map { |v| v.to_s.strip }.reject(&:blank?)
    lure = parts.join(" ")
    bait = bait_type.to_s.strip
    if lure.present? && bait.present?
      "#{lure} + #{bait}"
    else
      (lure.presence || bait.presence || "(unnamed bait)")
    end
  end

  private

  def at_least_one_attribute_present
    return if [color, weight, lure_type, bait_type].any? { |v| v.to_s.strip.present? }
    errors.add(:base, "at least one of color, weight, lure type, or bait must be set")
  end
end
