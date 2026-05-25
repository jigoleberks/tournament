require "application_system_test_case"

class CatchFormCameraZoomTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Joe")
    create(:species, club: @club, name: "Walleye")
  end

  test "zoom toggle is rendered in the DOM but stays hidden when the camera offers no 0.5x lens" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit new_catch_path

    # Cuprite runs Chromium with --use-fake-device-for-media-stream, which exposes
    # a single videoinput and no zoom capability. The capability probe should
    # find neither path, so the toggle wrapper must stay hidden.
    assert_selector "[data-photo-capture-target='zoomToggle']", visible: :all
    assert_no_selector "[data-photo-capture-target='zoomToggle']", visible: true
  end
end
