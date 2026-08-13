require "application_system_test_case"

# The home-page Notifications box on iOS. In a plain Safari tab (not installed
# to the home screen) iOS exposes neither PushManager nor Notification, so the
# box used to read a dead-end "push not supported" — and tapping Enable threw
# a raw ReferenceError into the status line. It must instead point at the fix:
# install the app to the Home Screen.
class PushRegisterTest < ApplicationSystemTestCase
  IOS_SAFARI_TAB_JS = <<~JS.freeze
    try { delete window.PushManager; } catch (e) {}
    try { delete window.Notification; } catch (e) {}
    Object.defineProperty(navigator, "userAgent", {
      configurable: true,
      get: () => "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    });
  JS

  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Joe")
  end

  test "an iOS Safari tab shows the install hint instead of a dead Enable button" do
    apply_ios_shims(extra_js: IOS_SAFARI_TAB_JS)
    sign_in_as(@user)
    visit root_path

    assert_text(/add to home screen/i, wait: 5)

    click_button "Enable"
    assert_no_text(/ReferenceError/)
    assert_text(/add to home screen/i)
  end

  test "a non-iOS browser without PushManager still reads push not supported" do
    apply_ios_shims(extra_js: "try { delete window.PushManager; } catch (e) {}")
    sign_in_as(@user)
    visit root_path

    assert_text("push not supported", wait: 5)
  end
end
