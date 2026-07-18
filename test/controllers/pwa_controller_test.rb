require "test_helper"

class PwaControllerTest < ActionDispatch::IntegrationTest
  # iOS rotates PWA push subscriptions (SW updates, OS events). Without a
  # pushsubscriptionchange handler the server hits ExpiredSubscription,
  # deletes the row, and the angler silently stops getting alerts while the
  # home-page toggle still reads "on".
  test "service worker ships the pushsubscriptionchange self-heal" do
    get "/service-worker.js"
    assert_response :success
    assert_includes response.body, "pushsubscriptionchange"
    assert_includes response.body, "/api/push_subscriptions/refresh"
    assert_includes response.body, VAPID[:public_key]
  end
end
