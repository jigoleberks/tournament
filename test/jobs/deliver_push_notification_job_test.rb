require "test_helper"

class DeliverPushNotificationJobTest < ActiveJob::TestCase
  # Intercept WebPush.payload_send by temporarily overriding the module method
  def with_webpush_stub(callable)
    original = WebPush.method(:payload_send)
    WebPush.define_singleton_method(:payload_send) { |**args| callable.call(**args) }
    yield
  ensure
    WebPush.singleton_class.remove_method(:payload_send)
    WebPush.define_singleton_method(:payload_send, original)
  end

  test "delivers a push to all subscriptions of the user" do
    user = create(:user)
    sub1 = create(:push_subscription, user: user)
    sub2 = create(:push_subscription, user: user)

    calls = []
    with_webpush_stub(->(**args) { calls << args[:endpoint] }) do
      payload = { user: user, title: "Hi", body: "Test", url: "/", reason: "bumped",
                  tournament: create(:tournament) }
      DeliverPushNotificationJob.perform_now(
        user_id: user.id, title: payload[:title], body: payload[:body], url: payload[:url],
        tournament_id: payload[:tournament].id
      )
    end
    assert_equal 2, calls.size
  end

  test "skips subscriptions that are muted globally" do
    user = create(:user)
    create(:push_subscription, user: user, muted_until: 1.hour.from_now)
    calls = 0
    with_webpush_stub(->(**) { calls += 1 }) do
      t = create(:tournament)
      DeliverPushNotificationJob.perform_now(user_id: user.id, title: "x", body: "y", url: "/", tournament_id: t.id)
    end
    assert_equal 0, calls
  end

  test "skips subscriptions that mute this tournament" do
    user = create(:user)
    t = create(:tournament)
    create(:push_subscription, user: user, muted_tournament_ids: [t.id])
    calls = 0
    with_webpush_stub(->(**) { calls += 1 }) do
      DeliverPushNotificationJob.perform_now(user_id: user.id, title: "x", body: "y", url: "/", tournament_id: t.id)
    end
    assert_equal 0, calls
  end
end
