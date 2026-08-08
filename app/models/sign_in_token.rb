require "securerandom"

class SignInToken < ApplicationRecord
  belongs_to :user
  belongs_to :club, optional: true
  belongs_to :issued_by_user, class_name: "User", optional: true

  CODE_TTL = 10.minutes
  CODE_MAX_ATTEMPTS = 5

  scope :open, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  def self.issue!(user:, club: nil, ttl: 30.minutes, issued_by: nil)
    create!(
      user: user,
      club: club || user.club_memberships.active.order(:created_at).first&.club,
      token: SecureRandom.uuid,
      expires_at: ttl.from_now,
      kind: "link",
      issued_by_user: issued_by
    )
  end

  # Open codes coexist — issuing must NOT invalidate the others. The magic-link
  # email path auto-issues a code from the public sign-in form, so invalidation
  # would let anyone who knows a member's email kill an organizer-issued code
  # mid-read-out. TTL and the attempt counter bound the open set instead.
  def self.issue_code!(user:, club: nil, issued_by: nil)
    create!(
      user: user,
      club: club || user.club_memberships.active.order(:created_at).first&.club,
      token: generate_code,
      expires_at: CODE_TTL.from_now,
      kind: "code",
      issued_by_user: issued_by
    )
  end

  def self.consume!(token_string)
    record = where(kind: "link").find_by(token: token_string)
    return nil if record.nil?
    return nil if record.expires_at < Time.current
    return nil if record.user.deactivated?

    return nil unless claim(record)
    record
  end

  def self.consume_code!(email:, code:)
    return nil if email.blank? || code.blank?

    user = User.find_by(email: email.to_s.strip)
    return nil unless user
    return nil if user.deactivated?

    records = where(user: user, kind: "code").open.order(created_at: :desc).to_a
    return nil if records.empty?

    match = records.find { |r| ActiveSupport::SecurityUtils.secure_compare(r.token, code.to_s.strip) }
    return claim(match) ? match : nil if match

    # A wrong try burns an attempt on every open SELF-ISSUED code — otherwise
    # requesting a fresh code would hand a brute-forcer a clean counter.
    # Set-based (two UPDATEs total, not one per open code): this is the
    # unauthenticated sign-in path, the easiest endpoint for a stranger to
    # hammer. Staff-issued codes (issued_by_user present) are exempt: the
    # public form auto-issues codes for any known email, so a shared burn
    # would let 5 wrong guesses from anyone kill an organizer-issued code
    # mid-read-out — the same grief coexistence (above) exists to prevent.
    # Their guess exposure is bounded by CODE_TTL and the per-IP+email rate
    # limit on submit_code instead.
    ids = records.select { |r| r.issued_by_user_id.nil? }.map(&:id)
    where(id: ids).update_all("attempts = attempts + 1")
    where(id: ids, used_at: nil).where(attempts: CODE_MAX_ATTEMPTS..).update_all(used_at: Time.current)
    nil
  end

  # Atomic claim — only one concurrent caller wins. The WHERE used_at IS NULL
  # is the guard: if a parallel request already consumed the row, update_all
  # returns 0 and we treat the call as a miss.
  def self.claim(record)
    where(id: record.id, used_at: nil).update_all(used_at: Time.current) == 1
  end
  private_class_method :claim

  def self.generate_code
    loop do
      code = SecureRandom.random_number(10**8).to_s.rjust(8, "0")
      return code unless exists?(token: code)
    end
  end
end
