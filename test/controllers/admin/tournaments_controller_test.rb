require "test_helper"

class Admin::TournamentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @walleye = create(:species, club: @club)
    sign_in_as(@organizer)
  end

  test "create permits format and blind_leaderboard like the organizers controller" do
    assert_difference "Tournament.count", 1 do
      post admin_tournaments_path, params: {
        tournament: {
          name: "Big Fish",
          mode: "solo",
          format: "big_fish_season",
          blind_leaderboard: true,
          starts_at: 1.hour.from_now,
          ends_at: 3.hours.from_now,
          scoring_slots_attributes: { "0" => { species_id: @walleye.id, slot_count: 1 } }
        }
      }
    end

    t = Tournament.last
    assert t.format_big_fish_season?, "format param should be permitted and persisted"
    assert t.blind_leaderboard?, "blind_leaderboard param should be permitted and persisted"
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
