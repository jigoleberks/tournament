require "application_system_test_case"

class LogCatchTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Joe")
    @walleye = create(:species, club: @club, name: "Walleye")
    @tournament = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now, name: "Wed Throwdown")
    create(:scoring_slot, tournament: @tournament, species: @walleye, slot_count: 2)
    entry = create(:tournament_entry, tournament: @tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)
  end

  test "angler logs a catch end-to-end" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)

    click_link "Log Catch"
    select "Walleye", from: "Species"
    fill_in "Length (in)", with: "20"
    attach_file "Photo", Rails.root.join("test/fixtures/files/sample_walleye.jpg")
    click_button "Submit"

    assert_text "Catch logged"
    assert_text "Wed Throwdown"
  end
end
