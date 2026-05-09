require "application_system_test_case"

class BigFishSeasonTournamentTest < ApplicationSystemTestCase
  test "leaderboard ranks members by single biggest walleye, with Biggest column header" do
    club = create(:club)
    walleye = create(:species, club: club, name: "Walleye")

    one_big   = create(:user, club: club, name: "One Big")
    grinder   = create(:user, club: club, name: "Grinder")

    tournament = build(:tournament, club: club, name: "Big Walleye Season",
                                    mode: :solo, format: :big_fish_season,
                                    starts_at: 1.hour.ago, ends_at: 1.day.from_now)
    tournament.save!(validate: false)
    create(:scoring_slot, tournament: tournament, species: walleye, slot_count: 3)
    tournament.reload

    e1 = create(:tournament_entry, tournament: tournament, name: "One Big")
    create(:tournament_entry_member, tournament_entry: e1, user: one_big)
    e2 = create(:tournament_entry, tournament: tournament, name: "Grinder")
    create(:tournament_entry_member, tournament_entry: e2, user: grinder)

    # One Big has a single 30" walleye.
    Catches::PlaceInSlots.call(catch: create(:catch, user: one_big, species: walleye, length_inches: 30))

    # Grinder has three 25" walleye — bigger total but smaller maximum.
    [25, 25, 25].each do |len|
      Catches::PlaceInSlots.call(catch: create(:catch, user: grinder, species: walleye, length_inches: len))
    end

    sign_in_as(one_big)
    visit tournament_path(tournament)

    # Header reads "Biggest", not "Total"
    assert_selector "th", text: "Biggest"
    assert_no_selector "th", text: "Total"

    # Row order: One Big leads (30") above Grinder (max 25" despite three fish).
    rows = page.all("#leaderboard tbody tr").map(&:text)
    assert_equal 2, rows.size
    assert_match(/One Big/, rows[0], "single 30\" walleye should outrank three 25\" walleye")
    assert_match(/Grinder/, rows[1])

    # Leader's scoring cell shows their biggest (30") not the sum (30 vs 75).
    leader_row = page.find("#leaderboard tbody tr:first-of-type")
    assert_match(/30/, leader_row.text)
    assert_no_match(/75/, leader_row.text)
  end

  private

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email
    click_button "Send sign-in link"
    visit consume_session_path(token: SignInToken.last.token)
  end
end
