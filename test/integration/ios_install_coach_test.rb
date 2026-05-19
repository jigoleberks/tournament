require "test_helper"

class IosInstallCoachTest < ActionDispatch::IntegrationTest
  # User agents must satisfy ApplicationController's `allow_browser versions: :modern`.
  IPHONE_UA  = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) " \
               "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"
  IPAD_UA    = "Mozilla/5.0 (iPad; CPU OS 17_6 like Mac OS X) " \
               "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"
  ANDROID_UA = "Mozilla/5.0 (Linux; Android 14; Pixel 8) " \
               "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
  DESKTOP_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
               "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

  test "renders the install banner for iPhone Safari" do
    get new_session_path, headers: { "HTTP_USER_AGENT" => IPHONE_UA }
    assert_response :success
    assert_select "#ios-install-coach"
    assert_match "Install this app to your home screen", response.body
    assert_match "Add to Home Screen", response.body
  end

  test "renders the install banner for iPad Safari" do
    get new_session_path, headers: { "HTTP_USER_AGENT" => IPAD_UA }
    assert_select "#ios-install-coach"
  end

  test "hides the install banner for Android Chrome" do
    get new_session_path, headers: { "HTTP_USER_AGENT" => ANDROID_UA }
    assert_select "#ios-install-coach", count: 0
  end

  test "hides the install banner for desktop browsers" do
    get new_session_path, headers: { "HTTP_USER_AGENT" => DESKTOP_UA }
    assert_select "#ios-install-coach", count: 0
  end

  test "hides the install banner when no user agent is sent" do
    get new_session_path
    assert_select "#ios-install-coach", count: 0
  end

  test "banner copy describes install benefits without overstating them" do
    # Guard against the pre-fix wording sneaking back: it claimed catches
    # don't upload outside the PWA, which became false after the
    # visibilitychange drain landed.
    get new_session_path, headers: { "HTTP_USER_AGENT" => IPHONE_UA }
    refute_match "reliable catch uploads only work once installed", response.body
    assert_match "Push notifications", response.body
  end
end
