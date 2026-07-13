require "application_system_test_case"

class RandomBagTournamentTest < ApplicationSystemTestCase
  setup do
    @club = Club.first || create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
  end

  test "selecting Random Bag reveals the range fields and forces blind on" do
    sign_in_as @organizer
    visit new_organizers_tournament_path

    select "Random Bag", from: "Format"
    assert_text "random target length"                       # from the format description
    assert_text "Random Bag target range"                    # the range section heading
    assert_field "Min (inches)"
    assert_field "Max (inches)"

    blind = find("input[type=checkbox][name='tournament[blind_leaderboard]']")
    assert blind.checked?, "blind is forced on for Random Bag"
    assert blind.matches_css?(".pointer-events-none"), "blind is locked"
  end

  test "switching away from Random Bag hides the range fields and restores blind" do
    sign_in_as @organizer
    visit new_organizers_tournament_path

    select "Random Bag", from: "Format"
    assert_text "Random Bag target range"

    # Bingo is the sharpest case: its bingo_not_blind validation forbids
    # blind_leaderboard = true, so a lingering forced-checked state would make
    # the form unsubmittable with no in-UI fix.
    select "Bingo", from: "Format"
    assert_no_text "Random Bag target range"
    blind = find("input[type=checkbox][name='tournament[blind_leaderboard]']")
    assert_not blind.checked?
    assert_not blind.matches_css?(".pointer-events-none")
  end

  private

  # Mirrors test/system/beat_the_average_tournament_test.rb.
  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email
    click_button "Send sign-in link"
    assert_text "Check your email"
    visit consume_session_path(token: SignInToken.last.token)
  end
end
