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

  test "tournaments action links an ended entrants-only row instead of showing the hint" do
    sign_in_member!
    t = create(:tournament, club: @club, name: "Locked League Night",
           awards_season_points: true, season_tag: "Spring 2026",
           starts_at: 6.days.ago, ends_at: 5.days.ago,
           entrants_only_leaderboard: true)
    get season_points_tournaments_path
    assert_response :success
    assert_match "Locked League Night", response.body
    assert_no_match "Ask an organizer to add you", response.body
    assert_select "a[href=?]", tournament_path(t)
  end

  test "standings page explains the tiered ladder in force" do
    create(:tournament, club: @club, awards_season_points: true, season_tag: "Spring 2026",
           starts_at: 6.days.ago, ends_at: 5.days.ago)
    sign_in_member!
    get season_points_path
    assert_response :success
    assert_includes response.body, "How points are awarded"
    assert_includes response.body, "9, 6, 3"
  end

  test "standings page explains full-field scoring without a ladder table" do
    @club.update!(season_points_scheme: :full_field)
    create(:tournament, club: @club, awards_season_points: true, season_tag: "Spring 2026",
           starts_at: 6.days.ago, ends_at: 5.days.ago)
    sign_in_member!
    get season_points_path
    assert_response :success
    assert_includes response.body, "every boat that scores"
    assert_not_includes response.body, "Boats out"
  end

  # FIX 5 regression: the explainer used to sample a fixed mid-band size (6)
  # for the 1–9 row. With season_points_min_entries raised to 8, that sampled
  # size fell below the minimum and rendered "—", telling members a 1–9 boat
  # night never pays placement points even though an 8- or 9-boat night does.
  # Sampling the TOP of the band (9) fixes it.
  test "standings page explainer shows the band still pays after a raised minimum" do
    @club.update!(season_points_min_entries: 8)
    create(:tournament, club: @club, awards_season_points: true, season_tag: "Spring 2026",
           starts_at: 6.days.ago, ends_at: 5.days.ago)
    sign_in_member!
    get season_points_path
    assert_response :success
    row = Nokogiri::HTML(response.body).css("tr").find { |tr| tr.text.include?("1–9") }
    assert row, "expected a 1–9 row in the explainer table"
    assert_not_includes row.text, "—"
  end

  test "standings page reports a customised attendance value and minimum" do
    @club.update!(season_points_attendance: 1, season_points_min_entries: 5)
    create(:tournament, club: @club, awards_season_points: true, season_tag: "Spring 2026",
           starts_at: 6.days.ago, ends_at: 5.days.ago)
    sign_in_member!
    get season_points_path
    assert_response :success
    assert_includes response.body, "1 points"
    assert_includes response.body, "5 entries"
  end
end
