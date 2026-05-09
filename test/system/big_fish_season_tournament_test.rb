require "application_system_test_case"

class BigFishSeasonTournamentTest < ApplicationSystemTestCase
  test "leaderboard shows one row per catch sorted by length, with Length column header" do
    club = create(:club)
    walleye = create(:species, club: club, name: "Walleye")

    galen     = create(:user, club: club, name: "Galen Patterson")
    galen_pc  = create(:user, club: club, name: "Galen PC")

    tournament = build(:tournament, club: club, name: "Big Walleye Season",
                                    mode: :solo, format: :big_fish_season,
                                    starts_at: 1.hour.ago, ends_at: 1.day.from_now)
    tournament.save!(validate: false)
    create(:scoring_slot, tournament: tournament, species: walleye, slot_count: 3)
    tournament.reload

    e1 = create(:tournament_entry, tournament: tournament, name: "Galen Patterson")
    create(:tournament_entry_member, tournament_entry: e1, user: galen)
    e2 = create(:tournament_entry, tournament: tournament, name: "Galen PC")
    create(:tournament_entry_member, tournament_entry: e2, user: galen_pc)

    # Galen Patterson: 25", 21", 18". Galen PC: 22".
    Catches::PlaceInSlots.call(catch: create(:catch, user: galen, species: walleye, length_inches: 25))
    Catches::PlaceInSlots.call(catch: create(:catch, user: galen, species: walleye, length_inches: 21))
    Catches::PlaceInSlots.call(catch: create(:catch, user: galen, species: walleye, length_inches: 18))
    Catches::PlaceInSlots.call(catch: create(:catch, user: galen_pc, species: walleye, length_inches: 22))

    sign_in_as(galen)
    visit tournament_path(tournament)

    # Header reads "Length", not "Biggest" or "Total"
    assert_selector "th", text: "Length"
    assert_no_selector "th", text: "Biggest"
    assert_no_selector "th", text: "Total"

    # Four rows, one per catch, ordered by length desc:
    #   1. Galen Patterson — 25
    #   2. Galen PC        — 22
    #   3. Galen Patterson — 21
    #   4. Galen Patterson — 18
    rows = page.all("#leaderboard tbody tr").map(&:text)
    assert_equal 4, rows.size
    assert_includes rows[0], "Galen Patterson"
    assert_includes rows[0], "25.0\""
    assert_includes rows[1], "Galen PC"
    assert_includes rows[1], "22.0\""
    assert_includes rows[2], "Galen Patterson"
    assert_includes rows[2], "21.0\""
    assert_includes rows[3], "Galen Patterson"
    assert_includes rows[3], "18.0\""
  end

  test "switching a draft tournament to Big Fish Season removes extra persisted slots" do
    club = create(:club)
    organizer = create(:user, club: club, role: :organizer, name: "Org")
    walleye = create(:species, club: club, name: "Walleye")
    pike    = create(:species, club: club, name: "Pike")

    tournament = create(:tournament, club: club, name: "Two Species Draft",
                                     mode: :solo, format: :standard,
                                     starts_at: 1.day.from_now, ends_at: 2.days.from_now)
    create(:scoring_slot, tournament: tournament, species: walleye, slot_count: 2)
    create(:scoring_slot, tournament: tournament, species: pike,    slot_count: 1)

    sign_in_as(organizer)
    visit edit_organizers_tournament_path(tournament)

    select "Big Fish Season", from: "Format"
    click_button "Update Tournament"

    assert_current_path organizers_tournaments_path
    tournament.reload
    assert tournament.big_fish_season?
    assert_equal 1, tournament.scoring_slots.count
    assert_equal walleye.id, tournament.scoring_slots.first.species_id
  end

  private

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email
    click_button "Send sign-in link"
    visit consume_session_path(token: SignInToken.last.token)
  end
end
