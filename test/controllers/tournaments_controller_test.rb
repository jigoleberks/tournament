require "test_helper"

class TournamentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    post session_path, params: { email: @user.email }
    get consume_session_path(token: SignInToken.last.token)
  end

  test "archived redirects to sign in when not signed in" do
    delete session_path
    get archived_tournaments_path
    assert_redirected_to new_session_path
  end

  test "archived returns 200 when signed in" do
    get archived_tournaments_path
    assert_response :success
  end

  test "archived includes tournaments ended more than 24h ago, newest first" do
    older = create(:tournament, club: @club, name: "Older", ends_at: 5.days.ago)
    newer = create(:tournament, club: @club, name: "Newer", ends_at: 26.hours.ago)
    get archived_tournaments_path
    assert_match "Older", response.body
    assert_match "Newer", response.body
    assert response.body.index("Newer") < response.body.index("Older"),
      "Newer (more recent ends_at) should appear before Older"
  end

  test "archived excludes tournaments ended within the last 24h" do
    create(:tournament, club: @club, name: "RecentlyEnded", ends_at: 2.hours.ago)
    get archived_tournaments_path
    assert_no_match "RecentlyEnded", response.body
  end

  test "archived excludes tournaments with no ends_at" do
    create(:tournament, club: @club, name: "OpenEnded", ends_at: nil)
    get archived_tournaments_path
    assert_no_match "OpenEnded", response.body
  end

  test "archived is scoped to the current user's club" do
    other_club = create(:club)
    create(:tournament, club: other_club, name: "OtherClubTourney", ends_at: 5.days.ago)
    get archived_tournaments_path
    assert_no_match "OtherClubTourney", response.body
  end
end
