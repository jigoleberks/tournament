class PushSubscription < ApplicationRecord
  belongs_to :user

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh, :auth, presence: true

  def muted?(at: Time.current)
    muted_until.present? && muted_until > at
  end

  def muted_for?(tournament)
    muted_tournament_ids.include?(tournament.id)
  end

  def to_webpush_endpoint
    { endpoint: endpoint, keys: { p256dh: p256dh, auth: auth } }
  end
end
