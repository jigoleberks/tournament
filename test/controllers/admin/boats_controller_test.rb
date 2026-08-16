require "test_helper"

class Admin::BoatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @kurtis = create(:user, club: @club, name: "Kurtis Sanguin", role: :member)
    @boat = create(:boat, club: @club, name: "Majestic Red", captain: @kurtis)
    @team = create(:tournament, club: @club, mode: :team,
                   starts_at: 1.hour.from_now, ends_at: 4.hours.from_now)
    sign_in_as(@organizer)
  end

  test "creating a boat in a solo tournament is refused" do
    solo = create(:tournament, club: @club, mode: :solo,
                  starts_at: 1.hour.from_now, ends_at: 4.hours.from_now)
    assert_no_difference ["Boat.count", "TournamentEntry.count"] do
      post admin_boats_path, params: {
        tournament_id: solo.id,
        boat: { name: "Red Rocket", captain_user_id: @kurtis.id }
      }
    end
    assert_equal "Boats are for team tournaments.", flash[:alert]
  end

  test "a retired boat is not offered as a near-match" do
    @boat.update!(active: false)
    assert_difference "Boat.count", 1 do
      post admin_boats_path, params: {
        tournament_id: @team.id,
        boat: { name: "Team Majestic Red", captain_user_id: @kurtis.id }
      }
    end
    assert_equal "Team Majestic Red", @team.tournament_entries.sole.name
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
