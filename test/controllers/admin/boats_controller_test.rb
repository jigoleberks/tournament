require "test_helper"

class Admin::BoatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @kurtis = create(:user, club: @club, name: "Kurtis Sanguin", role: :member)
    @boat = create(:boat, club: @club, name: "Majestic Red", captain: @kurtis)
    @team = create(:tournament, club: @club, mode: :team,
                   starts_at: 1.hour.from_now, ends_at: 4.hours.from_now)
    sign_in_as(@organizer)
  end

  test "creating a boat in a solo tournament is refused" do
    solo = create(:tournament, club: @club, mode: :solo,
                  starts_at: 1.hour.from_now, ends_at: 4.hours.from_now)
    assert_no_difference ["Boat.count", "TournamentEntry.count"] do
      post admin_boats_path, params: {
        tournament_id: solo.id,
        boat: { name: "Red Rocket", captain_user_id: @kurtis.id }
      }
    end
    assert_equal "Boats are for team tournaments.", flash[:alert]
  end

  test "a retired boat is not offered as a near-match" do
    @boat.update!(active: false)
    assert_difference "Boat.count", 1 do
      post admin_boats_path, params: {
        tournament_id: @team.id,
        boat: { name: "Team Majestic Red", captain_user_id: @kurtis.id }
      }
    end
    assert_equal "Team Majestic Red", @team.tournament_entries.sole.name
  end

  test "retiring a boat moves it out of the active list into a Retired section, not deleted" do
    delete admin_boat_path(@boat)
    assert_not @boat.reload.active
    get admin_boats_path
    assert_response :success
    assert_select "form[action=?]", admin_boat_path(@boat), count: 0
    assert_select "form[action=?]", restore_admin_boat_path(@boat), count: 1
    assert_match(/Retired/, response.body)
    assert_match(/Majestic Red/, response.body)
  end

  test "restoring a retired boat returns it to the active list" do
    @boat.update!(active: false)
    post restore_admin_boat_path(@boat)
    assert @boat.reload.active
    assert_redirected_to admin_boats_path
    get admin_boats_path
    assert_select "form[action=?]", admin_boat_path(@boat), count: 2
    assert_select "form[action=?]", restore_admin_boat_path(@boat), count: 0
  end

  test "index eager-loads captains instead of N+1 per row" do
    # See the organizers namespace's identical test for why this compares
    # query counts at 1 vs 3 boats rather than asserting an absolute cap.
    one_boat_queries = count_queries(/\bfrom\s+"?users"?/i) { get admin_boats_path }

    create(:boat, club: @club, name: "Big Tiller", captain: create(:user, club: @club, name: "Kent Pierce"))
    create(:boat, club: @club, name: "Red Rocket", captain: create(:user, club: @club, name: "Nate Rosengren"))

    three_boat_queries = count_queries(/\bfrom\s+"?users"?/i) { get admin_boats_path }

    assert_equal one_boat_queries, three_boat_queries,
                 "captain lookups should be batched, not scale with the number of boats"
  end

  test "entering a boat whose captain is already entered elsewhere redirects with an alert instead of crashing" do
    other_entry = create(:tournament_entry, tournament: @team, name: "Big Tiller")
    create(:tournament_entry_member, tournament_entry: other_entry, user: @kurtis)

    assert_no_difference "TournamentEntry.count" do
      post enter_admin_tournament_boat_path(tournament_id: @team.id, id: @boat.id)
    end
    assert_redirected_to edit_admin_tournament_path(@team)
    assert_match(/already entered/i, flash[:alert])
  end

  test "creating a new boat whose captain is already entered elsewhere redirects with an alert instead of crashing" do
    other_entry = create(:tournament_entry, tournament: @team, name: "Big Tiller")
    create(:tournament_entry_member, tournament_entry: other_entry, user: @kurtis)

    assert_difference "Boat.count", 1 do
      assert_no_difference "TournamentEntry.count" do
        post admin_boats_path, params: {
          tournament_id: @team.id,
          boat: { name: "Red Rocket", captain_user_id: @kurtis.id }
        }
      end
    end
    assert_match(/already entered/i, flash[:alert])
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
