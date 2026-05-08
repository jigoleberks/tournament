require "application_system_test_case"

class BlindLeaderboardTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  test "blind tournament hides fish and reorders rows so own entry leads, then reveals rank on end" do
    club = create(:club)
    walleye = create(:species, club: club)
    angler = create(:user, club: club, name: "Angler A")
    other = create(:user, club: club, name: "Angler B")

    tournament = create(:tournament, club: club, name: "League",
                        starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                        blind_leaderboard: true)
    create(:scoring_slot, tournament: tournament, species: walleye, slot_count: 1)

    # Names chosen so alphabetical order (Alpha, Zebra) is the OPPOSITE of rank
    # order (Alpha leads on length). This way row order proves the new behavior.
    my_entry = create(:tournament_entry, tournament: tournament, name: "Zebra Boat")
    create(:tournament_entry_member, tournament_entry: my_entry, user: angler)

    other_entry = create(:tournament_entry, tournament: tournament, name: "Alpha Boat")
    create(:tournament_entry_member, tournament_entry: other_entry, user: other)

    other_catch = create(:catch, user: other, species: walleye, length_inches: 30.0)
    create(:catch_placement, catch: other_catch, tournament: tournament,
                              tournament_entry: other_entry, species: walleye, slot_index: 0)

    sign_in_as(angler)
    visit tournament_path(tournament)

    assert_text(/Blind leaderboard/i)
    assert_no_text "30.0"

    blind_rows = page.all("#leaderboard tbody tr").map(&:text)
    assert_equal 2, blind_rows.size
    assert_match(/Zebra Boat/, blind_rows[0],
      "viewer's own entry should render first under blind mode, regardless of rank")
    assert_match(/Alpha Boat/, blind_rows[1],
      "other entry should render below the viewer's own entry under blind mode")

    travel_to(tournament.ends_at + 1.minute)
    perform_enqueued_jobs do
      TournamentLifecycleAnnounceJob.perform_now(tournament_id: tournament.id, kind: "ended")
    end

    visit tournament_path(tournament)
    assert_text "30.0"
    assert_no_text(/Blind leaderboard —/i)

    revealed_rows = page.all("#leaderboard tbody tr").map(&:text)
    assert_equal 2, revealed_rows.size
    assert_match(/Alpha Boat/, revealed_rows[0],
      "after reveal, rows return to rank order — Alpha Boat (30\") leads")
    assert_match(/Zebra Boat/, revealed_rows[1],
      "after reveal, the no-catch entry sits below the leading entry")
  ensure
    travel_back
  end

  private

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email
    click_button "Send sign-in link"
    visit consume_session_path(token: SignInToken.last.token)
  end
end
