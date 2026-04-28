require "securerandom"

class SignInToken < ApplicationRecord
  belongs_to :user

  def self.issue!(user:, ttl: 30.minutes)
    create!(user: user, token: SecureRandom.uuid, expires_at: ttl.from_now)
  end

  def self.consume!(token_string)
    record = find_by(token: token_string)
    return nil if record.nil?
    return nil if record.used_at.present?
    return nil if record.expires_at < Time.current

    record.update!(used_at: Time.current)
    record.user
  end
end
