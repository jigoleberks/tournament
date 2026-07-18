require "test_helper"

class Api::PushSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    sign_in_as(@user)
  end

  test "POST creates a subscription" do
    assert_difference "PushSubscription.count", 1 do
      post "/api/push_subscriptions", params: {
        subscription: { endpoint: "https://e/1", keys: { p256dh: "p", auth: "a" } }
      }, headers: { "Accept" => "application/json" }
    end
    assert_response :created
  end

  test "POST is idempotent on endpoint" do
    create(:push_subscription, user: @user, endpoint: "https://e/2")
    assert_no_difference "PushSubscription.count" do
      post "/api/push_subscriptions", params: {
        subscription: { endpoint: "https://e/2", keys: { p256dh: "p2", auth: "a2" } }
      }, headers: { "Accept" => "application/json" }
    end
    assert PushSubscription.find_by(endpoint: "https://e/2").p256dh == "p2"
  end

  test "DELETE removes a subscription" do
    sub = create(:push_subscription, user: @user, endpoint: "https://e/3")
    delete "/api/push_subscriptions", params: { endpoint: sub.endpoint }, headers: { "Accept" => "application/json" }
    assert_response :no_content
    assert_nil PushSubscription.find_by(endpoint: "https://e/3")
  end

  test "creating a subscription records push_subscribed with endpoint host" do
    user = create(:user)
    sign_in_as(user)

    assert_difference -> { user.user_events.push_subscribed.count }, 1 do
      post "/api/push_subscriptions", params: {
        subscription: { endpoint: "https://fcm.googleapis.com/abc", keys: { p256dh: "k", auth: "a" } }
      }, headers: { "Accept" => "application/json" }
    end
    assert_equal "fcm.googleapis.com", user.user_events.push_subscribed.last.metadata["endpoint_host"]
  end

  test "idempotent re-save does not record a second push_subscribed" do
    user = create(:user)
    sign_in_as(user)
    create(:push_subscription, user: user, endpoint: "https://fcm.googleapis.com/abc")

    assert_no_difference -> { user.user_events.push_subscribed.count } do
      post "/api/push_subscriptions", params: {
        subscription: { endpoint: "https://fcm.googleapis.com/abc", keys: { p256dh: "k2", auth: "a2" } }
      }, headers: { "Accept" => "application/json" }
    end
  end

  test "re-registering an endpoint that belonged to another user reassigns it" do
    other = create(:user)
    stale = PushSubscription.create!(user: other, endpoint: "https://push.example/shared-ep",
                                     p256dh: "oldkey", auth: "oldauth")
    post "/api/push_subscriptions", params: {
      subscription: { endpoint: "https://push.example/shared-ep",
                      keys: { p256dh: "newkey", auth: "newauth" } }
    }, as: :json
    assert_response :created
    stale.reload
    assert_equal @user.id, stale.user_id
    assert_equal "newkey", stale.p256dh
  end

  # POST /api/push_subscriptions/refresh — the service worker's
  # pushsubscriptionchange self-heal. APNs/FCM rotate endpoints behind our
  # back; the SW re-subscribes and swaps the stored row so alerts keep
  # arriving instead of dying silently on ExpiredSubscription.

  test "refresh rotates an existing subscription to the new endpoint and keys" do
    create(:push_subscription, user: @user, endpoint: "https://e/old", p256dh: "p", auth: "a")
    assert_no_difference "PushSubscription.count" do
      post "/api/push_subscriptions/refresh", params: {
        old_endpoint: "https://e/old",
        subscription: { endpoint: "https://e/new", keys: { p256dh: "p2", auth: "a2" } }
      }, as: :json
    end
    assert_response :no_content
    assert_nil PushSubscription.find_by(endpoint: "https://e/old")
    sub = PushSubscription.find_by(endpoint: "https://e/new")
    assert_equal @user.id, sub.user_id
    assert_equal "p2", sub.p256dh
  end

  # Possession of a previously-registered endpoint is one ownership proof
  # (endpoints are unguessable capability URLs). Without a matching row AND
  # without a CSRF token the request proves nothing and must not create
  # anything.
  test "refresh with an unknown old endpoint and no CSRF token is a 404 no-op" do
    with_forgery_protection do
      assert_no_difference "PushSubscription.count" do
        post "/api/push_subscriptions/refresh", params: {
          old_endpoint: "https://e/never-registered",
          subscription: { endpoint: "https://e/new", keys: { p256dh: "p", auth: "a" } }
        }, as: :json
      end
      assert_response :not_found
    end
  end

  # The rotation case the self-heal exists for: delivery already destroyed the
  # row on ExpiredSubscription (or the browser fired pushsubscriptionchange
  # with no oldSubscription), so possession can't be proven. The SW fetches a
  # CSRF token from /api/session — the same same-origin proof create relies
  # on — and the new subscription must be stored, not 404'd away.
  test "refresh with a dead old endpoint but a valid CSRF token stores the new subscription" do
    with_forgery_protection do
      assert_difference "PushSubscription.count", 1 do
        post "/api/push_subscriptions/refresh", params: {
          old_endpoint: "https://e/already-destroyed",
          subscription: { endpoint: "https://e/rotated", keys: { p256dh: "p2", auth: "a2" } }
        }, headers: { "X-CSRF-Token" => api_session_csrf_token }, as: :json
      end
      assert_response :no_content
      sub = PushSubscription.find_by(endpoint: "https://e/rotated")
      assert_equal @user.id, sub.user_id
      assert_equal "p2", sub.p256dh
    end
  end

  test "refresh with a null old endpoint but a valid CSRF token stores the new subscription" do
    with_forgery_protection do
      assert_difference "PushSubscription.count", 1 do
        post "/api/push_subscriptions/refresh", params: {
          old_endpoint: nil,
          subscription: { endpoint: "https://e/rotated2", keys: { p256dh: "p", auth: "a" } }
        }, headers: { "X-CSRF-Token" => api_session_csrf_token }, as: :json
      end
      assert_response :no_content
      assert_equal @user.id, PushSubscription.find_by(endpoint: "https://e/rotated2").user_id
    end
  end

  test "refresh requires sign-in" do
    create(:push_subscription, user: @user, endpoint: "https://e/old")
    reset!
    post "/api/push_subscriptions/refresh", params: {
      old_endpoint: "https://e/old",
      subscription: { endpoint: "https://e/new", keys: { p256dh: "p", auth: "a" } }
    }, as: :json
    assert_response :unauthorized
  end

  # A service worker has no page, no csrf meta tag, no token. refresh must be
  # exempt from CSRF verification (while create stays protected — its
  # null_session turns a tokenless POST into a 401).
  test "refresh works without a CSRF token while create stays protected" do
    with_forgery_protection do
      create(:push_subscription, user: @user, endpoint: "https://e/old")

      post "/api/push_subscriptions/refresh", params: {
        old_endpoint: "https://e/old",
        subscription: { endpoint: "https://e/new", keys: { p256dh: "p", auth: "a" } }
      }, as: :json
      assert_response :no_content

      post "/api/push_subscriptions", params: {
        subscription: { endpoint: "https://e/other", keys: { p256dh: "p", auth: "a" } }
      }, as: :json
      assert_response :unauthorized
    end
  end

  test "destroying a subscription records push_unsubscribed" do
    user = create(:user)
    sign_in_as(user)
    user.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/abc", p256dh: "k", auth: "a")

    assert_difference -> { user.user_events.push_unsubscribed.count }, 1 do
      delete "/api/push_subscriptions", params: { endpoint: "https://fcm.googleapis.com/abc" },
             headers: { "Accept" => "application/json" }
    end
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end

  def with_forgery_protection
    old_setting = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = old_setting
  end

  # The token the same way the service worker gets it: from the drain-preflight
  # session endpoint.
  def api_session_csrf_token
    get "/api/session", headers: { "Accept" => "application/json" }
    JSON.parse(response.body).fetch("csrf_token")
  end
end
