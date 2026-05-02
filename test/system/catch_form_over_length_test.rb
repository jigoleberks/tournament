require "application_system_test_case"

class CatchFormOverLengthTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Joe")
    @walleye = create(:species, club: @club, name: "Walleye")
    @tournament = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: @tournament, species: @walleye, slot_count: 2)
    entry = create(:tournament_entry, tournament: @tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)
  end

  test "Walleye over 50 inches surfaces an inline failure and does not submit" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit new_catch_path

    select "Walleye", from: "Species"
    fill_in "Length (in)", with: "60"
    click_button "Submit"

    # Cap check fires before the photo check, so we don't need to attach a photo.
    assert_text "can't exceed 50"

    # And the form did not navigate away (the Stimulus submit short-circuits).
    assert_current_path new_catch_path
  end

  test "Walleye over 50 inches: live feedback appears as the user types" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit new_catch_path

    select "Walleye", from: "Species"
    fill_in "Length (in)", with: "60"

    # No submit click — refresh() runs on input event and writes to status target.
    assert_text "can't exceed 50"
  end
end
