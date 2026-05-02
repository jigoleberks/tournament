require "application_system_test_case"

class BottomNavTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
  end

  test "bottom nav shows Home and Refresh" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit root_path

    assert_selector "nav a[aria-label='Home']"
    assert_selector "nav button[aria-label='Refresh'][data-controller~='app-refresh']"
  end
end
