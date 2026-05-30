require "test_helper"

class OfflinePageTest < ActionDispatch::IntegrationTest
  test "GET /offline renders without a signed-in user" do
    get "/offline"
    assert_response :success
    assert_select "h1", text: /log catch/i
  end

  test "offline page does not require authentication and shows no user chrome" do
    get "/offline"
    assert_response :success
    # No bottom-nav / personalized chrome — the cached page must be user-agnostic.
    assert_select "nav", count: 0
    # No CSRF meta tag: the cached shell must carry no per-session token.
    assert_select "meta[name=csrf-token]", count: 0
  end
end
