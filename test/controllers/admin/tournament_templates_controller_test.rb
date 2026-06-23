require "test_helper"

class Admin::TournamentTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(@organizer)
  end

  test "create accepts season_tag" do
    assert_difference -> { TournamentTemplate.count }, 1 do
      post admin_tournament_templates_path, params: {
        tournament_template: { name: "Wednesday League", mode: "solo", season_tag: "2026" }
      }
    end
    assert_redirected_to admin_tournament_templates_path
    assert_equal "2026", TournamentTemplate.last.season_tag
  end

  test "create permits format and blind_leaderboard like the organizers controller" do
    walleye = create(:species, club: @club)
    assert_difference -> { TournamentTemplate.count }, 1 do
      post admin_tournament_templates_path, params: {
        tournament_template: {
          name: "Big Fish League",
          mode: "solo",
          format: "big_fish_season",
          blind_leaderboard: true,
          tournament_template_scoring_slots_attributes: { "0" => { species_id: walleye.id, slot_count: 1 } }
        }
      }
    end

    t = TournamentTemplate.last
    assert t.format_big_fish_season?, "format param should be permitted and persisted"
    assert t.blind_leaderboard?, "blind_leaderboard param should be permitted and persisted"
  end

  test "POST clone carries the template's season_tag onto the tournament" do
    walleye = create(:species, club: @club)
    template = create(:tournament_template, club: @club, name: "Monthly Walleye", season_tag: "2026")
    template.tournament_template_scoring_slots.create!(species: walleye, slot_count: 1)

    post clone_admin_tournament_template_path(template),
         params: { starts_at: 1.day.from_now, ends_at: 1.day.from_now + 4.hours }

    assert_equal "2026", Tournament.last.season_tag
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
