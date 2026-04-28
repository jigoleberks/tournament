require "test_helper"

class PushSubscriptionTest < ActiveSupport::TestCase
  setup { @user = create(:user) }

  test "endpoint is unique" do
    create(:push_subscription, user: @user, endpoint: "https://example/abc")
    duplicate = build(:push_subscription, user: @user, endpoint: "https://example/abc")
    assert_not duplicate.valid?
  end

  test "muted? respects muted_until" do
    sub = create(:push_subscription, user: @user, muted_until: 1.hour.from_now)
    assert sub.muted?
    sub.update!(muted_until: 1.minute.ago)
    assert_not sub.muted?
  end

  test "mutes a specific tournament" do
    t = create(:tournament)
    sub = create(:push_subscription, user: @user, muted_tournament_ids: [t.id])
    assert sub.muted_for?(t)
  end
end
