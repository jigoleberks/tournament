require "test_helper"

class Admin::BoatsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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

  test "renaming a boat keeps its captain" do
    patch admin_boat_path(@boat), params: { boat: { name: "Majestic Red II", captain_user_id: @kurtis.id } }
    assert_equal "Majestic Red II", @boat.reload.name
    assert_equal @kurtis, @boat.captain
  end

  test "renaming a boat cascades the new name to its entries, including a finished tournament" do
    finished = create(:tournament, club: @club, mode: :team,
                       starts_at: 2.days.ago, ends_at: 1.day.ago)
    finished_entry = create(:tournament_entry, tournament: finished, name: "Majestic Red", boat: @boat)
    live_entry = create(:tournament_entry, tournament: @team, name: "Majestic Red", boat: @boat)

    patch admin_boat_path(@boat), params: { boat: { name: "Majestic Red II", captain_user_id: @kurtis.id } }

    assert_equal "Majestic Red II", finished_entry.reload.name
    assert_equal "Majestic Red II", live_entry.reload.name
  end

  test "renaming a boat does not touch an entry whose name was deliberately edited away from it" do
    entry = create(:tournament_entry, tournament: @team, name: "Majestic Red - DQ'd", boat: @boat)

    patch admin_boat_path(@boat), params: { boat: { name: "Majestic Red II", captain_user_id: @kurtis.id } }

    assert_equal "Majestic Red - DQ'd", entry.reload.name
  end

  test "changing only the captain does not touch entries" do
    other_captain = create(:user, club: @club, name: "Other Captain")
    entry = create(:tournament_entry, tournament: @team, name: "Majestic Red", boat: @boat)

    patch admin_boat_path(@boat), params: { boat: { name: "Majestic Red", captain_user_id: other_captain.id } }

    assert_equal "Majestic Red", entry.reload.name
    assert_equal other_captain, @boat.reload.captain
  end

  test "renaming a boat re-broadcasts the leaderboard for every affected tournament" do
    finished = create(:tournament, club: @club, mode: :team,
                       starts_at: 2.days.ago, ends_at: 1.day.ago)
    create(:tournament_entry, tournament: finished, name: "Majestic Red", boat: @boat)
    create(:tournament_entry, tournament: @team, name: "Majestic Red", boat: @boat)

    tournament_ids = with_broadcast_spy do
      perform_enqueued_jobs do
        patch admin_boat_path(@boat), params: { boat: { name: "Majestic Red II", captain_user_id: @kurtis.id } }
      end
    end

    assert_equal [finished.id, @team.id].sort, tournament_ids.sort
  end

  test "renaming a boat enqueues the redraw rather than broadcasting inline in the request" do
    create(:tournament_entry, tournament: @team, name: "Majestic Red", boat: @boat)

    assert_enqueued_with(job: BroadcastBoatRenameJob) do
      patch admin_boat_path(@boat), params: { boat: { name: "Majestic Red II", captain_user_id: @kurtis.id } }
    end
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
  # The picker lists active boats only, but the page is a snapshot: one
  # organizer can retire a boat while another still has the row on screen.
  # Tapping it then went around the Restore flow entirely.
  test "entering a retired boat points at Restore instead of entering it" do
    @boat.update!(active: false)

    assert_no_difference "TournamentEntry.count" do
      post enter_admin_tournament_boat_path(tournament_id: @team.id, id: @boat.id)
    end

    assert_redirected_to admin_boats_path
    assert_match(/retired/i, flash[:alert])
    assert_match(/Restore/, flash[:alert])
  end

  # A boat keeps its captain after they leave the club (see Boat), so it stays
  # in the picker — but the tap must not seat a departed angler, which is what
  # the per-member controls on the same screen already refuse.
  test "entering a boat whose captain has left the club is refused" do
    @kurtis.update!(deactivated_at: 1.day.ago)

    assert_no_difference "TournamentEntry.count" do
      post enter_admin_tournament_boat_path(tournament_id: @team.id, id: @boat.id)
    end

    assert_match(/Kurtis Sanguin has left the club/, flash[:alert])
    assert_match(/Reassign/, flash[:alert])
  end

  # Creating refuses a near-match; renaming has to as well, or the rename
  # recreates the exact Majestic Red / Magestic Red split the guard prevents.
  test "renaming a boat onto another boat's near-match is refused" do
    other = create(:boat, club: @club, name: "Magestic Red", captain: @organizer)

    patch admin_boat_path(other),
          params: { boat: { name: "Team Majestic Red", captain_user_id: @organizer.id } }

    assert_equal "Magestic Red", other.reload.name
    assert_match(/Majestic Red is already a boat/, flash[:alert])
  end

  test "renaming a boat to a variant of its own name is still allowed" do
    patch admin_boat_path(@boat),
          params: { boat: { name: "Team Majestic Red", captain_user_id: @kurtis.id } }

    assert_equal "Team Majestic Red", @boat.reload.name
  end

  # Retire is reversible and keeps history attached. Delete is the escape hatch
  # for a boat that should never have existed — a duplicate spelling, a typo, a
  # seed proposal that came out wrong — and is gated behind Retire so a boat
  # still in the picker can't be destroyed by one stray tap.
  test "deleting a retired boat removes it permanently" do
    @boat.update!(active: false)

    assert_difference "Boat.count", -1 do
      delete purge_admin_boat_path(@boat)
    end
    assert_redirected_to admin_boats_path
    assert_match(/deleted/i, flash[:notice])
  end

  # The property that makes Delete safe to offer at all: boat_id is read by the
  # picker, the rename cascade and "same as last week", never by
  # Leaderboards::Build, which ranks off the entry and its own name column.
  test "deleting a retired boat leaves its entries and their names standing, only unlinked" do
    finished = create(:tournament, club: @club, mode: :team,
                      starts_at: 2.days.ago, ends_at: 1.day.ago)
    entry = create(:tournament_entry, tournament: finished, name: "Majestic Red", boat: @boat)
    @boat.update!(active: false)

    assert_no_difference "TournamentEntry.count" do
      delete purge_admin_boat_path(@boat)
    end

    assert_nil entry.reload.boat_id
    assert_equal "Majestic Red", entry.name
  end

  # The Delete button renders only in the Retired section, but the page is a
  # snapshot — another organizer can restore a boat while this one still has
  # the row on screen, the same race #enter guards against.
  test "deleting a boat that is still active is refused" do
    assert_no_difference "Boat.count" do
      delete purge_admin_boat_path(@boat)
    end
    assert_match(/retire/i, flash[:alert])
  end

  test "deleting a boat in another club is out of reach" do
    other = create(:boat, club: create(:club), name: "Someone Else's Boat", active: false)

    assert_no_difference "Boat.count" do
      delete purge_admin_boat_path(other)
    end
    assert_response :not_found
  end

  test "the Retired section offers Delete alongside Restore, naming how many entries it unlinks" do
    finished = create(:tournament, club: @club, mode: :team,
                      starts_at: 2.days.ago, ends_at: 1.day.ago)
    create(:tournament_entry, tournament: finished, name: "Majestic Red", boat: @boat)
    @boat.update!(active: false)

    get admin_boats_path

    assert_select "form[action=?]", purge_admin_boat_path(@boat), count: 1
    assert_select "form[action=?]", restore_admin_boat_path(@boat), count: 1
    assert_match(/1 past entry/, response.body)
  end

  test "the Delete confirmation on a boat with no history does not mention entries" do
    @boat.update!(active: false)

    get admin_boats_path

    assert_select "form[action=?]", purge_admin_boat_path(@boat), count: 1
    assert_no_match(/past entr/, response.body)
  end

  # See the captain eager-loading test above for why this compares query counts
  # at 1 vs 3 retired boats rather than asserting an absolute cap.
  test "the retired list counts entries in one query rather than one per boat" do
    @boat.update!(active: false)
    one_boat = count_queries(/\bfrom\s+"?tournament_entries"?/i) { get admin_boats_path }

    create(:boat, club: @club, name: "Old Tiller", active: false)
    create(:boat, club: @club, name: "Old Pearl", active: false)

    three_boats = count_queries(/\bfrom\s+"?tournament_entries"?/i) { get admin_boats_path }

    assert_equal one_boat, three_boats,
                 "entry counts should be batched, not scale with the retired list"
  end

end
