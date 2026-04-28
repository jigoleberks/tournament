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

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
