class Bait < ApplicationRecord
  belongs_to :user
  has_many :catches, dependent: :restrict_with_error

  scope :active,   -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  ATTR_MAX_LEN = 64
  validates :color, :weight, :lure_type, :bait_type, :plastic, :plastic_color,
            length: { maximum: ATTR_MAX_LEN }, allow_blank: true
  validate :at_least_one_attribute_present

  # Standard jig weights offered as tap-chips on the bait form; free text
  # remains possible for anything unusual.
  COMMON_WEIGHTS = [
    "1/16 oz", "1/8 oz", "3/16 oz", "1/4 oz", "5/16 oz",
    "3/8 oz", "1/2 oz", "5/8 oz", "3/4 oz", "1 oz"
  ].freeze

  # Starter chips shown before the angler has built up their own vocabulary.
  STARTER_VOCAB = {
    colors:   ["white", "chartreuse", "orange", "pink", "blue", "green"],
    lures:    ["jighead", "fireball"],
    plastics: ["twister grub", "tube jig", "frog"],
    tippings: ["minnow", "crawler", "leech"]
  }.freeze

  # Tap-chip options per attribute: everything this user has ever entered
  # (archived combos included — retiring a combo shouldn't shrink the
  # vocabulary), merged with the starters, deduped case-insensitively.
  # Shared by the bait form and the catch form's quick-add panel.
  def self.chip_vocab(user)
    baits = user.baits
    {
      colors:   merged_vocab(:colors, baits.pluck(:color) + baits.pluck(:plastic_color)),
      lures:    merged_vocab(:lures, baits.pluck(:lure_type)),
      plastics: merged_vocab(:plastics, baits.pluck(:plastic)),
      tippings: merged_vocab(:tippings, baits.pluck(:bait_type))
    }
  end

  def self.merged_vocab(key, values)
    (values.map { |v| v.to_s.strip }.reject(&:blank?) + STARTER_VOCAB[key])
      .uniq(&:downcase)
  end
  private_class_method :merged_vocab

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  # Composed from up to three groups — lure, plastic, tipping — joined with " + ":
  #   "3/8 oz orange fireball + minnow"
  #   "1/4 oz white jighead + white twister grub"
  #   "1/4 oz chartreuse jighead + pink tube jig + minnow"
  def display_name
    lure    = [weight, color, lure_type].map { |v| v.to_s.strip }.reject(&:blank?).join(" ")
    plastic_part = [plastic_color, plastic].map { |v| v.to_s.strip }.reject(&:blank?).join(" ")
    tipping = bait_type.to_s.strip
    groups = [lure, plastic_part, tipping].reject(&:blank?)
    groups.any? ? groups.join(" + ") : "(unnamed bait)"
  end

  private

  def at_least_one_attribute_present
    return if [color, weight, lure_type, bait_type, plastic, plastic_color].any? { |v| v.to_s.strip.present? }
    errors.add(:base, "at least one of color, weight, lure type, plastic, or bait must be set")
  end
end
