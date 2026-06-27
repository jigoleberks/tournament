require "test_helper"

module Diagnostics
  class RecordVisitTest < ActiveSupport::TestCase
    setup { @user = create(:user) }

    test "first visit records device_changed and app_build_changed" do
      RecordVisit.call(user: @user, user_agent: "Safari/1", app_build: "build-a")

      kinds = @user.user_events.pluck(:kind).sort
      assert_equal ["app_build_changed", "device_changed"], kinds
      assert @user.reload.last_seen_at.present?
    end

    test "unchanged repeat visit (after throttle reset) records nothing new" do
      RecordVisit.call(user: @user, user_agent: "Safari/1", app_build: "build-a")
      @user.update_column(:last_seen_at, 2.hours.ago) # clear the throttle window
      RecordVisit.call(user: @user, user_agent: "Safari/1", app_build: "build-a")

      assert_equal 2, @user.user_events.count # still just the first pair
    end

    test "changed app build records only app_build_changed" do
      RecordVisit.call(user: @user, user_agent: "Safari/1", app_build: "build-a")
      @user.update_column(:last_seen_at, 2.hours.ago)
      RecordVisit.call(user: @user, user_agent: "Safari/1", app_build: "build-b")

      assert_equal 1, @user.user_events.app_build_changed.where(app_build: "build-b").count
      # the unchanged UA must not add a second device_changed
      assert_equal 1, @user.user_events.device_changed.count
    end

    test "throttled within the hour records nothing" do
      @user.update_column(:last_seen_at, 5.minutes.ago)
      RecordVisit.call(user: @user, user_agent: "Safari/1", app_build: "build-a")
      assert_equal 0, @user.user_events.count
    end

    test "nil user is a no-op and does not raise" do
      assert_nothing_raised { RecordVisit.call(user: nil, user_agent: "x", app_build: "y") }
    end
  end
end
