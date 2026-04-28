require "application_system_test_case"

class PreTripTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
  end

  test "pre-trip page shows checks" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit pre_trip_path

    assert_text "Pre-trip check"
    assert_selector "[data-check='session']"
    assert_selector "[data-check='camera']"
    assert_selector "[data-check='gps']"
    assert_selector "[data-check='clock']"
    assert_selector "[data-check='notifications']"
    assert_selector "[data-check='network']"
  end
end
