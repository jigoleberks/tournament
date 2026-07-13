require "test_helper"

class TournamentsBingoTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)  # factory associates user to the club
    # Magic-link sign-in (same pattern as TournamentsControllerTest#setup).
    post session_path, params: { email: @user.email }
    get consume_session_path(token: SignInToken.last.token)

    @walleye, = create_bingo_species!
    @t = Tournament.new(club: @club, name: "Bingo Night", mode: :solo, format: :bingo,
                        starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
    @t.save!
    @entry = @t.tournament_entries.create!
    @entry.tournament_entry_members.create!(user: @user)
  end

  test "bingo card page renders the 5x5 grid for the current user's entry" do
    create(:catch, user: @user, species: @walleye, length_inches: 15,
                   captured_at_device: 1.hour.ago)
    get bingo_card_tournament_path(@t)
    assert_response :success
    assert_select "[data-bingo-cell]", 25
    assert_select "#bingo_card"
  end

  test "tournament show renders the bingo leaderboard partial" do
    get tournament_path(@t)
    assert_response :success
    assert_select "#leaderboard"
  end
end
