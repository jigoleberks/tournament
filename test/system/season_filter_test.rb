require "application_system_test_case"

class SeasonFilterTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @open_water = create(:tournament, club: @club, name: "OW Wed", season_tag: "Open Water 2026", starts_at: 1.hour.ago)
    @ice = create(:tournament, club: @club, name: "Ice Friday", season_tag: "Ice 2026/27", starts_at: 1.hour.ago)
  end

  test "filters tournaments by season tag" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit tournaments_path

    assert_text "OW Wed"
    assert_text "Ice Friday"

    click_link "Open Water 2026"
    assert_text "OW Wed"
    assert_no_text "Ice Friday"
  end
end
