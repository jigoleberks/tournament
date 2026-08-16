require "application_system_test_case"

class BoatEntryTest < ApplicationSystemTestCase
  setup do
    @club = create(:club, name: "Test Anglers")
    @organizer = create(:user, club: @club, role: :organizer, name: "Organizer One")
    @kurtis = create(:user, club: @club, role: :member, name: "Kurtis Sanguin")
    @kent = create(:user, club: @club, role: :member, name: "Kent Pierce")
    create(:boat, club: @club, name: "Majestic Red", captain: @kurtis)
    create(:boat, club: @club, name: "Big Tiller", captain: @kent)

    group = SecureRandom.uuid
    @main = create(:tournament, club: @club, mode: :team, name: "League Night Main",
                   starts_at: 1.hour.from_now, ends_at: 4.hours.from_now, link_group_id: group)
    @side = create(:tournament, club: @club, mode: :team, name: "League Night Side",
                   starts_at: 1.hour.from_now, ends_at: 4.hours.from_now, link_group_id: group)
    create(:scoring_slot, tournament: @main, species: create(:species, name: "Walleye"))
  end

  test "tapping a boat enters it in both tournaments" do
    token = SignInToken.issue!(user: @organizer)
    visit consume_session_path(token: token.token)

    visit edit_organizers_tournament_path(@main)
    assert_text "Big Tiller — Kent Pierce"
    assert_text "Majestic Red — Kurtis Sanguin"

    click_button "Majestic Red — Kurtis Sanguin"
    assert_text "Majestic Red entered."

    visit edit_organizers_tournament_path(@side)
    assert_text "Majestic Red"
    assert_text "Kurtis Sanguin"
  end

  test "a new boat is created and entered from the entry form" do
    token = SignInToken.issue!(user: @organizer)
    visit consume_session_path(token: token.token)

    visit edit_organizers_tournament_path(@main)
    find("summary", text: "+ New boat…").click
    fill_in "boat[name]", with: "Red Rocket"
    select "Kent Pierce", from: "boat[captain_user_id]"
    click_button "Create and enter"

    assert_text "Red Rocket entered."
    # Once entered, the boat drops out of the "Add a boat" picker (which is
    # where the "Name — Captain" label lives) and shows up as an entry
    # instead: entry.name plus its team member list. Assert on what the
    # entries section actually renders rather than the picker's format.
    within("li", text: "Red Rocket") do
      assert_text "Kent Pierce", wait: 5
    end
  end
end
