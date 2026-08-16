require "test_helper"

class Organizers::BoatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @kurtis = create(:user, club: @club, name: "Kurtis Sanguin", role: :member)
    @boat = create(:boat, club: @club, name: "Majestic Red", captain: @kurtis)
    @team = create(:tournament, club: @club, mode: :team,
                   starts_at: 1.hour.from_now, ends_at: 4.hours.from_now)
    sign_in_as(@organizer)
  end

  test "entering a boat creates the entry with the captain aboard" do
    assert_difference "TournamentEntry.count", 1 do
      post enter_organizers_tournament_boat_path(tournament_id: @team.id, id: @boat.id)
    end
    entry = @team.tournament_entries.sole
    assert_equal "Majestic Red", entry.name
    assert_equal [@kurtis], entry.users
    assert_equal "Majestic Red entered.", flash[:notice]
  end

  test "entering the same boat twice is a no-op" do
    post enter_organizers_tournament_boat_path(tournament_id: @team.id, id: @boat.id)
    assert_no_difference "TournamentEntry.count" do
      post enter_organizers_tournament_boat_path(tournament_id: @team.id, id: @boat.id)
    end
  end

  test "a solo tournament refuses a boat" do
    solo = create(:tournament, club: @club, mode: :solo,
                  starts_at: 1.hour.from_now, ends_at: 4.hours.from_now)
    assert_no_difference "TournamentEntry.count" do
      post enter_organizers_tournament_boat_path(tournament_id: solo.id, id: @boat.id)
    end
    assert_equal "Boats are for team tournaments.", flash[:alert]
  end

  test "creating a new boat enters it in the same submit" do
    assert_difference ["Boat.count", "TournamentEntry.count"], 1 do
      post organizers_boats_path, params: {
        tournament_id: @team.id,
        boat: { name: "Red Rocket", captain_user_id: @kurtis.id }
      }
    end
    assert_equal "Red Rocket", @team.tournament_entries.sole.name
  end

  test "a near-match name is refused with a suggestion rather than duplicated" do
    assert_no_difference "Boat.count" do
      post organizers_boats_path, params: {
        tournament_id: @team.id,
        boat: { name: "  majestic   RED  ", captain_user_id: @kurtis.id }
      }
    end
    assert_match(/Did you mean Majestic Red\?/, flash[:alert])
  end

  test "creating a boat in a solo tournament is refused" do
    solo = create(:tournament, club: @club, mode: :solo,
                  starts_at: 1.hour.from_now, ends_at: 4.hours.from_now)
    assert_no_difference ["Boat.count", "TournamentEntry.count"] do
      post organizers_boats_path, params: {
        tournament_id: solo.id,
        boat: { name: "Red Rocket", captain_user_id: @kurtis.id }
      }
    end
    assert_equal "Boats are for team tournaments.", flash[:alert]
  end

  test "a retired boat is not offered as a near-match" do
    @boat.update!(active: false)
    assert_difference "Boat.count", 1 do
      post organizers_boats_path, params: {
        tournament_id: @team.id,
        boat: { name: "Team Majestic Red", captain_user_id: @kurtis.id }
      }
    end
    assert_equal "Team Majestic Red", @team.tournament_entries.sole.name
  end

  test "a near-match already entered in this tournament says so instead of pointing at an absent row" do
    post enter_organizers_tournament_boat_path(tournament_id: @team.id, id: @boat.id)
    assert_no_difference "Boat.count" do
      post organizers_boats_path, params: {
        tournament_id: @team.id,
        boat: { name: "Team Majestic Red", captain_user_id: @kurtis.id }
      }
    end
    assert_equal "Majestic Red is already entered.", flash[:alert]
  end

  test "members are forbidden" do
    sign_in_as(@kurtis)
    post enter_organizers_tournament_boat_path(tournament_id: @team.id, id: @boat.id)
    assert_response :forbidden
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
