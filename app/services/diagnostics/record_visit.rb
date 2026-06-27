module Diagnostics
  # Called on every request via a throttled before_action. Records device and
  # app-build *changes* only (deduped against the last sighting) so the activity
  # log never gets one row per request. Best-effort: never raises into a request.
  class RecordVisit
    def self.call(user:, user_agent:, app_build:)
      return unless user
      return if user.last_seen_at && user.last_seen_at > ::User::LAST_SEEN_THROTTLE.ago

      user.touch_last_seen!

      # Snapshot both prior values BEFORE writing anything so neither
      # check is polluted by the other's newly-inserted row.
      last_ua    = last_value(user, :with_user_agent, :user_agent)
      last_build = last_value(user, :with_app_build, :app_build)

      if user_agent.present? && user_agent != last_ua
        ::UserEvent.record!(user: user, kind: :device_changed, user_agent: user_agent, app_build: app_build)
      end

      if app_build.present? && app_build != last_build
        ::UserEvent.record!(user: user, kind: :app_build_changed, user_agent: user_agent, app_build: app_build)
      end
    rescue StandardError => e
      Rails.logger.warn("Diagnostics::RecordVisit failed: #{e.class}: #{e.message}")
    end

    def self.last_value(user, scope, column)
      user.user_events.public_send(scope).recent.limit(1).pick(column)
    end
    private_class_method :last_value
  end
end
