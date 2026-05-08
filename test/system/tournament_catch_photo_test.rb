require "application_system_test_case"

class TournamentCatchPhotoTest < ApplicationSystemTestCase
  test "member opens and closes a catch photo modal on a non-blind tournament" do
    club = create(:club)
    walleye = create(:species, club: club, name: "Walleye")
    angler = create(:user, club: club, name: "Angler A", role: :member)
    other  = create(:user, club: club, name: "Angler B", role: :member)

    tournament = create(:tournament, club: club, name: "Open League",
                        starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                        blind_leaderboard: false)
    create(:scoring_slot, tournament: tournament, species: walleye, slot_count: 1)

    my_entry = create(:tournament_entry, tournament: tournament, name: "My Boat")
    create(:tournament_entry_member, tournament_entry: my_entry, user: angler)

    other_entry = create(:tournament_entry, tournament: tournament, name: "Other Boat")
    create(:tournament_entry_member, tournament_entry: other_entry, user: other)

    other_catch = create(:catch, user: other, species: walleye, length_inches: 22.5,
                                  captured_at_device: 30.minutes.ago)
    create(:catch_placement, catch: other_catch, tournament: tournament,
                              tournament_entry: other_entry, species: walleye, slot_index: 0)

    sign_in_as(angler)
    visit tournament_path(tournament)

    # The leaderboard fish link for "Other Boat" should target the modal frame.
    fish_link = find("a", text: /Walleye.*22\.5/, match: :first)
    assert_equal "catch_photo_modal", fish_link["data-turbo-frame"]

    fish_link.click

    # Modal content should appear inside the frame.
    within "turbo-frame#catch_photo_modal" do
      assert_selector "img"
      assert_text "Walleye"
      assert_text "22.5"
      assert_text other.name
    end

    # Close button empties the frame.
    within "turbo-frame#catch_photo_modal" do
      find("button[aria-label=Close]").click
    end

    # Frame is now empty (no children).
    assert_selector "turbo-frame#catch_photo_modal:empty", visible: :all

    # Click again — modal reopens with fresh content.
    find("a", text: /Walleye.*22\.5/, match: :first).click
    within "turbo-frame#catch_photo_modal" do
      assert_selector "img"
    end
  end

  test "member sees fish as plain text (not a link) on a blind tournament leaderboard" do
    club = create(:club)
    walleye = create(:species, club: club, name: "Walleye")
    angler = create(:user, club: club, name: "Angler A", role: :member)
    other  = create(:user, club: club, name: "Angler B", role: :member)

    tournament = create(:tournament, club: club, name: "Blind League",
                        starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                        blind_leaderboard: true)
    create(:scoring_slot, tournament: tournament, species: walleye, slot_count: 1)

    my_entry = create(:tournament_entry, tournament: tournament, name: "My Boat")
    create(:tournament_entry_member, tournament_entry: my_entry, user: angler)

    other_entry = create(:tournament_entry, tournament: tournament, name: "Other Boat")
    create(:tournament_entry_member, tournament_entry: other_entry, user: other)

    # angler's own catch — visible to the angler under :own_entry_only scope.
    own_catch = create(:catch, user: angler, species: walleye, length_inches: 19.0,
                                captured_at_device: 30.minutes.ago)
    create(:catch_placement, catch: own_catch, tournament: tournament,
                              tournament_entry: my_entry, species: walleye, slot_index: 0)

    sign_in_as(angler)
    visit tournament_path(tournament)

    # The angler's own fish row IS visible (label rendered) but should not be a link
    # under the new `catch_link_target` rule for blind tournaments.
    assert_text(/Walleye.*19\.0/)
    assert_no_selector "a", text: /Walleye.*19\.0/
  end

  test "member can open a photo modal on a blind tournament that has ended" do
    club = create(:club)
    walleye = create(:species, name: "Walleye", club: club)
    angler = create(:user, club: club, name: "Angler A", role: :member)
    other  = create(:user, club: club, name: "Angler B", role: :member)

    # Tournament whose blind window is OVER (ends_at < now). Members should now see links.
    tournament = create(:tournament, club: club, name: "Ended Blind",
                        starts_at: 2.hours.ago, ends_at: 1.hour.ago,
                        blind_leaderboard: true)
    create(:scoring_slot, tournament: tournament, species: walleye, slot_count: 1)

    my_entry = create(:tournament_entry, tournament: tournament, name: "My Boat")
    create(:tournament_entry_member, tournament_entry: my_entry, user: angler)

    other_entry = create(:tournament_entry, tournament: tournament, name: "Other Boat")
    create(:tournament_entry_member, tournament_entry: other_entry, user: other)

    other_catch = create(:catch, user: other, species: walleye, length_inches: 22.5,
                                  captured_at_device: 90.minutes.ago)
    create(:catch_placement, catch: other_catch, tournament: tournament,
                              tournament_entry: other_entry, species: walleye, slot_index: 0)

    sign_in_as(angler)
    visit tournament_path(tournament)

    fish_link = find("a", text: /Walleye.*22\.5/, match: :first)
    assert_equal "catch_photo_modal", fish_link["data-turbo-frame"]

    fish_link.click

    within "turbo-frame#catch_photo_modal" do
      assert_selector "img"
      assert_text "Walleye"
      assert_text "22.5"
    end
  end

  test "organizer link still goes to full /catches/:id (no Turbo Frame)" do
    club = create(:club)
    walleye = create(:species, club: club, name: "Walleye")
    organizer = create(:user, club: club, name: "Organizer O", role: :organizer)
    other = create(:user, club: club, name: "Angler B", role: :member)

    tournament = create(:tournament, club: club, name: "Open League",
                        starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                        blind_leaderboard: false)
    create(:scoring_slot, tournament: tournament, species: walleye, slot_count: 1)

    other_entry = create(:tournament_entry, tournament: tournament, name: "Other Boat")
    create(:tournament_entry_member, tournament_entry: other_entry, user: other)

    other_catch = create(:catch, user: other, species: walleye, length_inches: 22.5,
                                  captured_at_device: 30.minutes.ago)
    create(:catch_placement, catch: other_catch, tournament: tournament,
                              tournament_entry: other_entry, species: walleye, slot_index: 0)

    sign_in_as(organizer)
    visit tournament_path(tournament)

    fish_link = find("a", text: /Walleye.*22\.5/, match: :first)
    assert_match %r{/catches/#{other_catch.id}\?}, fish_link[:href],
      "organizer should link to /catches/:id, not the framed tournament_catch_path"
    assert_nil fish_link["data-turbo-frame"],
      "organizer link should not have data-turbo-frame attribute"
  end

  private

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email
    click_button "Send sign-in link"
    visit consume_session_path(token: SignInToken.last.token)
  end
end
