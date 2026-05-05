require "application_system_test_case"

class BlindLeaderboardTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  test "blind tournament hides other entries' fish until ends_at" do
    club = create(:club)
    walleye = create(:species, club: club)
    angler = create(:user, club: club, name: "Angler A")
    other = create(:user, club: club, name: "Angler B")

    tournament = create(:tournament, club: club, name: "League",
                        starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                        blind_leaderboard: true)
    create(:scoring_slot, tournament: tournament, species: walleye, slot_count: 1)

    my_entry = create(:tournament_entry, tournament: tournament, name: "My Boat")
    create(:tournament_entry_member, tournament_entry: my_entry, user: angler)

    other_entry = create(:tournament_entry, tournament: tournament, name: "Other Boat")
    create(:tournament_entry_member, tournament_entry: other_entry, user: other)

    other_catch = create(:catch, user: other, species: walleye, length_inches: 30.0)
    create(:catch_placement, catch: other_catch, tournament: tournament,
                              tournament_entry: other_entry, species: walleye, slot_index: 0)

    sign_in_as(angler)
    visit tournament_path(tournament)

    assert_text "My Boat"
    assert_text "Other Boat"
    assert_no_text "30.0"
    assert_text(/Blind leaderboard/i)

    travel_to(tournament.ends_at + 1.minute)
    perform_enqueued_jobs do
      TournamentLifecycleAnnounceJob.perform_now(tournament_id: tournament.id, kind: "ended")
    end

    visit tournament_path(tournament)
    assert_text "30.0"
    assert_no_text(/Blind leaderboard —/i)
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
