class UserEvent < ApplicationRecord
  belongs_to :user

  # Append-only audit log (no updated_at). Mirrors the JudgeAction pattern.
  enum :kind, {
    sign_in_succeeded: 0,
    sign_in_failed:    1,
    device_changed:    2,
    app_build_changed: 3,
    push_subscribed:   4,
    push_unsubscribed: 5,
    push_muted:        6
  }

  scope :recent,          -> { order(created_at: :desc) }
  scope :with_user_agent, -> { where.not(user_agent: nil) }
  scope :with_app_build,  -> { where.not(app_build: nil) }

  # Most-recent non-null value of `column` among `user`'s events, narrowed by
  # `scope` (e.g. :with_user_agent). Single source of truth for "last sighting"
  # lookups — backs both RecordVisit's change detection and the diagnostics card.
  def self.last_value(user, scope, column)
    user.user_events.public_send(scope).recent.limit(1).pick(column)
  end

  # Single write path. Best-effort: never raises into a user request.
  def self.record!(user:, kind:, user_agent: nil, app_build: nil, **metadata)
    create!(user: user, kind: kind, user_agent: user_agent, app_build: app_build, metadata: metadata)
  rescue StandardError => e
    Rails.logger.warn("UserEvent.record! failed: #{e.class}: #{e.message}")
    nil
  end
end
