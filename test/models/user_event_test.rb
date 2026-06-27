# test/models/user_event_test.rb
require "test_helper"

class UserEventTest < ActiveSupport::TestCase
  setup { @user = create(:user) }

  test "record! writes columns and folds extras into metadata" do
    event = UserEvent.record!(
      user: @user, kind: :sign_in_succeeded,
      user_agent: "UA/1.0", app_build: "abc123",
      ip: "1.2.3.4", method: "code"
    )

    assert event.persisted?
    assert_equal "sign_in_succeeded", event.kind
    assert_equal "UA/1.0", event.user_agent
    assert_equal "abc123", event.app_build
    assert_equal "1.2.3.4", event.metadata["ip"]
    assert_equal "code", event.metadata["method"]
  end

  test "record! swallows errors and returns nil instead of raising" do
    # nil user violates the belongs_to; record! must not raise
    assert_nothing_raised do
      assert_nil UserEvent.record!(user: nil, kind: :sign_in_failed)
    end
  end

  test "recent orders newest first; with_user_agent filters nulls" do
    old = UserEvent.record!(user: @user, kind: :device_changed, user_agent: "old")
    old.update_column(:created_at, 2.hours.ago)
    UserEvent.record!(user: @user, kind: :push_muted) # no user_agent
    new = UserEvent.record!(user: @user, kind: :device_changed, user_agent: "new")

    assert_equal new, @user.user_events.recent.first
    assert_equal ["new", "old"], @user.user_events.with_user_agent.recent.pluck(:user_agent)
  end
end
