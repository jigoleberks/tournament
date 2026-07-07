require "application_system_test_case"

class SpeciesSelectionTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Angler")
    @tournament = create(:tournament, club: @club,
                         starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    @entry = create(:tournament_entry, tournament: @tournament)
    create(:tournament_entry_member, tournament_entry: @entry, user: @user)
    @species = create(:species, club: @club, name: "Walleye")
    sign_in_as(@user)
  end

  test "solo angler picks a species before reaching the catch form" do
    visit tournament_path(@tournament)
    click_on "Log Catch"

    # Species chooser step
    assert_text "What did you catch?"
    click_on @species.name

    # Catch form shows the chosen species read-only, with a Change affordance
    assert_text "Species: #{@species.name}"
    assert_link "Change"
    assert_no_selector "select#catch_species_id:not(.hidden)"
  end

  test "team angler picks a teammate then a species before reaching the catch form" do
    @tournament.update!(mode: :team)
    teammate = create(:user, club: @club, name: "Boatmate")
    create(:tournament_entry_member, tournament_entry: @entry, user: teammate)

    visit tournament_path(@tournament)
    click_on "Log Catch"

    # Teammate chooser step
    assert_text "Who's this catch for?"
    click_on "Myself"

    # Species chooser step
    assert_text "What did you catch?"
    click_on @species.name

    # Catch form shows the chosen species read-only, with a Change affordance
    assert_text "Species: #{@species.name}"
    assert_link "Change"
    assert_no_selector "select#catch_species_id:not(.hidden)"
  end

  private

  def sign_in_as(user)
    SignInToken.issue!(user: user)
    visit consume_session_path(token: SignInToken.last.token)
  end
end
