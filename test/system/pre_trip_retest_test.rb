require "application_system_test_case"

class PreTripRetestTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
  end

  test "Re-test visibly resets rows to … before re-running checks" do
    skip "Needs --use-fake-device-for-media-stream Cuprite flag; CI Chromium has no real camera so the row settles on '✗ Requested device not found' before the assertion runs."
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit pre_trip_path

    # Wait for the initial run to settle on the always-synchronous session check.
    assert_selector "[data-pre-trip-target='session']", text: "✓"

    click_button "Re-test"

    # Camera check is async (awaits getUserMedia); after click and before the
    # async check resolves, the row should display "…" because _reset() ran
    # synchronously at the start of runAll().
    assert_selector "[data-pre-trip-target='camera']", text: "…"

    # And it eventually settles again.
    assert_selector "[data-pre-trip-target='camera']", text: /✓|✗|⚠/
  end
end
