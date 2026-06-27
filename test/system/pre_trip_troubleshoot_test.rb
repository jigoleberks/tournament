require "application_system_test_case"

class PreTripTroubleshootTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
  end

  test "Reset camera zoom clears the persisted lens state" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit pre_trip_path

    # Simulate a phone wedged on the ultra-wide with a blocklisted lens.
    page.execute_script(<<~JS)
      localStorage.setItem("catchCameraZoom", "0.5")
      localStorage.setItem("catchCameraBlockedWideLens", '["abc"]')
    JS

    find("summary", text: "Troubleshooting").click
    click_button "Reset camera zoom"

    assert_selector "[data-pre-trip-target='troubleshootStatus']", text: /reset/i
    assert_nil page.evaluate_script("localStorage.getItem('catchCameraZoom')")
    assert_nil page.evaluate_script("localStorage.getItem('catchCameraBlockedWideLens')")
  end
end
