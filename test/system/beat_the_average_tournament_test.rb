require "application_system_test_case"

class BeatTheAverageTournamentTest < ApplicationSystemTestCase
  setup do
    @club = Club.first || create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
  end

  test "organizer sees Beat the Average in the format select with forced blind checkbox" do
    sign_in_as @organizer
    visit new_organizers_tournament_path

    select "Beat the Average", from: "Format"
    assert_text "hidden running average"
    assert_text "Every catch counts toward one combined average; the slot count is ignored."

    blind = find("input[type=checkbox][name='tournament[blind_leaderboard]']")
    assert blind.checked?
  end

  private

  # Mirrors the helper used by test/system/progressive_length_tournament_test.rb.
  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email
    click_button "Send sign-in link"
    assert_text "Check your email"  # wait for the POST to commit the token before reading it
    visit consume_session_path(token: SignInToken.last.token)
  end
end
