require "application_system_test_case"

class EditSpeciesTest < ApplicationSystemTestCase
  test "judge changes a catch's species via the catch show page" do
    club = create(:club)
    walleye = create(:species, name: "Walleye", club: club)
    pike    = create(:species, name: "Pike",    club: club)
    judge = create(:user, club: club, name: "Judge J")
    angler = create(:user, club: club, name: "Angler A")

    tournament = create(:tournament, club: club, name: "Open League",
                        starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                        blind_leaderboard: false)
    create(:scoring_slot, tournament: tournament, species: walleye, slot_count: 1)
    create(:scoring_slot, tournament: tournament, species: pike,    slot_count: 1)
    create(:tournament_judge, tournament: tournament, user: judge)

    entry = create(:tournament_entry, tournament: tournament, name: "Solo Boat")
    create(:tournament_entry_member, tournament_entry: entry, user: angler)

    catch_record = create(:catch, user: angler, species: walleye, length_inches: 22.5,
                                  captured_at_device: 30.minutes.ago)
    Catches::PlaceInSlots.call(catch: catch_record)

    assert catch_record.catch_placements.active.where(species: walleye).exists?,
      "precondition: catch is placed in walleye slot"

    sign_in_as(judge)
    visit catch_path(catch_record, t: tournament.id)

    assert_text(/Edit species & length/i)
    select "Pike", from: "species_id"
    click_button "Save"

    # Returns to the judges catch path; verify the catch's species changed.
    catch_record.reload
    assert_equal pike.id, catch_record.species_id

    # Visit the leaderboard and confirm the catch is now under "Pike".
    visit tournament_path(tournament)
    assert_text(/Pike/)
    assert_no_text(/Walleye.*22\.5/)
  end

  private

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email
    click_button "Send sign-in link"
    visit consume_session_path(token: SignInToken.last.token)
  end
end
