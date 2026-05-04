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

  test "leaderboard redirects to sign in when not signed in" do
    delete session_path
    tournament = create(:tournament, club: @club)
    get leaderboard_tournament_path(tournament)
    assert_redirected_to new_session_path
  end

  test "leaderboard returns 200 when signed in" do
    tournament = create(:tournament, club: @club)
    get leaderboard_tournament_path(tournament)
    assert_response :success
  end

  test "leaderboard renders the leaderboard partial with entry rows" do
    tournament = create(:tournament, club: @club)
    species = create(:species, club: @club)
    create(:scoring_slot, tournament: tournament, species: species, slot_count: 1)
    entry = create(:tournament_entry, tournament: tournament, name: "Team Reel Deal")
    create(:tournament_entry_member, tournament_entry: entry, user: @user)
    catch_record = create(:catch, user: @user, species: species, length_inches: 18.5)
    create(:catch_placement, catch: catch_record, tournament: tournament,
                              tournament_entry: entry, species: species, slot_index: 0)

    get leaderboard_tournament_path(tournament)
    assert_response :success
    assert_match "Team Reel Deal", response.body
    assert_match "leaderboard", response.body
  end

  test "show renders the ends label and date/time on the same line, date right-aligned" do
    ends_at = Time.zone.local(2026, 6, 15, 18, 30)
    tournament = create(:tournament, club: @club, ends_at: ends_at)
    get tournament_path(tournament)
    assert_response :success
    assert_select "[class~='justify-between']" do
      assert_select "*", text: /Ends|Ended/
      assert_select "*", text: /Jun 15, 2026 ·\s+6:30 PM/
    end
  end

  test "leaderboard shows a green check beside an approved fish and an 'Approved by NAME' tag" do
    tournament = create(:tournament, club: @club)
    species = create(:species, club: @club)
    create(:scoring_slot, tournament: tournament, species: species, slot_count: 1)
    entry = create(:tournament_entry, tournament: tournament, name: "Team Reel Deal")
    create(:tournament_entry_member, tournament_entry: entry, user: @user)
    catch_record = create(:catch, user: @user, species: species, length_inches: 18.5)
    create(:catch_placement, catch: catch_record, tournament: tournament,
                              tournament_entry: entry, species: species, slot_index: 0)
    judge = create(:user, club: @club, name: "Judge Judy")
    create(:judge_action, judge_user: judge, catch: catch_record, action: :approve)

    get leaderboard_tournament_path(tournament)
    assert_response :success
    assert_select "[data-test=approved-check]", count: 1
    assert_match "Approved by Judge Judy", response.body
  end

  test "leaderboard does not render approved markers for unreviewed fish" do
    tournament = create(:tournament, club: @club)
    species = create(:species, club: @club)
    create(:scoring_slot, tournament: tournament, species: species, slot_count: 1)
    entry = create(:tournament_entry, tournament: tournament, name: "Team Reel Deal")
    create(:tournament_entry_member, tournament_entry: entry, user: @user)
    catch_record = create(:catch, user: @user, species: species, length_inches: 18.5)
    create(:catch_placement, catch: catch_record, tournament: tournament,
                              tournament_entry: entry, species: species, slot_index: 0)

    get leaderboard_tournament_path(tournament)
    assert_response :success
    assert_select "[data-test=approved-check]", count: 0
    assert_no_match "Approved by", response.body
  end

  test "leaderboard 404s for tournaments outside the current user's club" do
    other_club = create(:club)
    other_tournament = create(:tournament, club: other_club)
    get leaderboard_tournament_path(other_tournament)
    assert_response :not_found
  end
end
