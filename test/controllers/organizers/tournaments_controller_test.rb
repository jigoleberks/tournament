require "test_helper"

class Organizers::TournamentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @member = create(:user, club: @club, role: :member)
    @organizer = create(:user, club: @club, role: :organizer)
  end

  test "members are forbidden" do
    sign_in_as(@member)
    get organizers_tournaments_path
    assert_response :forbidden
  end

  test "organizers can list tournaments" do
    sign_in_as(@organizer)
    create(:tournament, club: @club, name: "Wednesday Throwdown")
    get organizers_tournaments_path
    assert_response :success
    assert_match "Wednesday Throwdown", response.body
  end

  test "organizers can create a tournament with scoring slots" do
    sign_in_as(@organizer)
    species = create(:species, club: @club, name: "Walleye")
    assert_difference -> { Tournament.count } => 1, -> { ScoringSlot.count } => 1 do
      post organizers_tournaments_path, params: {
        tournament: {
          name: "Wed Night",
          kind: "event",
          mode: "solo",
          starts_at: 1.day.from_now,
          ends_at: 1.day.from_now + 4.hours,
          season_tag: "Open Water 2026",
          scoring_slots_attributes: { "0" => { species_id: species.id, slot_count: 3 } }
        }
      }
    end
    assert_redirected_to organizers_tournaments_path
  end

  test "create accepts local: false" do
    organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(organizer)
    assert_difference -> { @club.tournaments.count }, 1 do
      post organizers_tournaments_path, params: {
        tournament: { name: "Away Trip", kind: "event", mode: "solo",
                      starts_at: Time.current, ends_at: 1.day.from_now,
                      local: "0" }
      }
    end
    assert_equal false, @club.tournaments.last.local
  end

  test "create defaults local to true when checkbox omitted" do
    organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(organizer)
    post organizers_tournaments_path, params: {
      tournament: { name: "Local Trip", kind: "event", mode: "solo",
                    starts_at: Time.current, ends_at: 1.day.from_now }
    }
    assert_equal true, @club.tournaments.last.local
  end

  test "index shows (away) tag for non-local tournaments" do
    organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(organizer)
    away = create(:tournament, club: @club, local: false, name: "Out of Town",
                               starts_at: 1.day.from_now)
    get organizers_tournaments_path
    assert_response :success
    assert_match "(away)", response.body
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
