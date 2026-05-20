require "test_helper"

class SeasonPointsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @member = create(:user, club: @club)
  end

  def sign_in_member!
    token = SignInToken.issue!(user: @member)
    get consume_session_path(token: token.token)
  end

  test "show requires sign-in" do
    get season_points_path
    assert_redirected_to new_session_path
  end

  test "show renders an empty state when no points-eligible tournaments" do
    sign_in_member!
    get season_points_path
    assert_response :success
    assert_match(/No season-points tournaments configured/i, response.body)
  end

  test "tournaments action renders an empty state when none ended" do
    sign_in_member!
    get season_points_tournaments_path
    assert_response :success
  end

  test "tournaments action shows the leaderboard hint on a locked entrants-only row" do
    sign_in_member!
    create(:tournament, club: @club, name: "Locked League Night",
           awards_season_points: true, season_tag: "Spring 2026",
           starts_at: 6.days.ago, ends_at: 5.days.ago,
           entrants_only_leaderboard: true)
    get season_points_tournaments_path
    assert_response :success
    assert_match "Locked League Night", response.body
    assert_match "Ask an organizer to add you", response.body
  end
end
