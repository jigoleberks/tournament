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

  test "results renders the standings sheet for an organizer" do
    t = create(:tournament, club: @club, starts_at: 2.hours.ago, ends_at: 1.hour.ago)
    create(:scoring_slot, tournament: t, species: @walleye, slot_count: 1)
    angler = create(:user, club: @club, name: "Reel Biggun")
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: angler)
    create(:catch, user: angler, species: @walleye, length_inches: 21,
                   captured_at_device: 90.minutes.ago).tap { |c| Catches::PlaceInSlots.call(catch: c) }

    get results_admin_tournament_path(t)
    assert_response :success
    assert_select "table"
    assert_includes @response.body, "Reel Biggun"
  end

  test "results is forbidden for a non-organizer member" do
    member = create(:user, club: @club, role: :member)
    t = create(:tournament, club: @club, starts_at: 2.hours.ago, ends_at: 1.hour.ago)
    sign_in_as(member)
    get results_admin_tournament_path(t)
    assert_response :forbidden
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
