module DiagnosticsHelper
  def current_device(user)
    Diagnostics::Device.parse(UserEvent.last_value(user, :with_user_agent, :user_agent))
  end

  def current_app_build(user)
    UserEvent.last_value(user, :with_app_build, :app_build)
  end

  def app_build_stale?(build)
    build.present? && build != ::AppVersion.current
  end

  USER_EVENT_LABELS = {
    "sign_in_succeeded" => "Signed in",
    "sign_in_failed"    => "Sign-in failed",
    "device_changed"    => "Device changed",
    "app_build_changed" => "App updated",
    "push_subscribed"   => "Notifications on",
    "push_unsubscribed" => "Notifications off",
    "push_muted"        => "Notifications muted"
  }.freeze

  def user_event_label(event)
    USER_EVENT_LABELS.fetch(event.kind, event.kind.humanize)
  end
end
