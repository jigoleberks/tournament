require "test_helper"

class Organizers::TournamentTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(@organizer)
  end

  test "POST clone creates a tournament" do
    walleye = create(:species, club: @club)
    template = create(:tournament_template, club: @club, name: "Monthly Walleye")
    template.tournament_template_scoring_slots.create!(species: walleye, slot_count: 1)

    assert_difference "Tournament.count", 1 do
      post clone_organizers_tournament_template_path(template),
           params: { starts_at: 1.day.from_now, ends_at: 1.day.from_now + 4.hours }
    end
    assert_redirected_to organizers_tournaments_path
  end

  test "create accepts awards_season_points: true" do
    assert_difference -> { TournamentTemplate.count }, 1 do
      post organizers_tournament_templates_path, params: {
        tournament_template: {
          name: "Wednesday League",
          mode: "solo",
          awards_season_points: "1"
        }
      }
    end
    assert_redirected_to organizers_tournament_templates_path
    assert TournamentTemplate.last.awards_season_points?
  end

  test "creates a template with blind_leaderboard set" do
    assert_difference -> { TournamentTemplate.count }, 1 do
      post organizers_tournament_templates_path, params: {
        tournament_template: { name: "Blind Night Template", mode: "solo", blind_leaderboard: "1" }
      }
    end
    assert_redirected_to organizers_tournament_templates_path
    assert TournamentTemplate.last.blind_leaderboard?
  end

  test "create accepts format: big_fish_season with one scoring slot" do
    walleye = create(:species, club: @club)
    assert_difference -> { TournamentTemplate.count }, 1 do
      post organizers_tournament_templates_path, params: {
        tournament_template: {
          name: "BFS Monthly", mode: "solo", format: "big_fish_season",
          tournament_template_scoring_slots_attributes: {
            "0" => { species_id: walleye.id, slot_count: 1 }
          }
        }
      }
    end
    assert_redirected_to organizers_tournament_templates_path
    assert TournamentTemplate.last.format_big_fish_season?
  end

  test "create accepts format: hidden_length with one scoring slot" do
    walleye = create(:species, club: @club)
    assert_difference -> { TournamentTemplate.count }, 1 do
      post organizers_tournament_templates_path, params: {
        tournament_template: {
          name: "HL Monthly", mode: "solo", format: "hidden_length",
          tournament_template_scoring_slots_attributes: {
            "0" => { species_id: walleye.id, slot_count: 1 }
          }
        }
      }
    end
    assert_redirected_to organizers_tournament_templates_path
    assert TournamentTemplate.last.format_hidden_length?
  end

  test "create accepts format: biggest_vs_smallest with one scoring slot" do
    walleye = create(:species, club: @club)
    assert_difference -> { TournamentTemplate.count }, 1 do
      post organizers_tournament_templates_path, params: {
        tournament_template: {
          name: "BvS Monthly", mode: "solo", format: "biggest_vs_smallest",
          tournament_template_scoring_slots_attributes: {
            "0" => { species_id: walleye.id, slot_count: 1 }
          }
        }
      }
    end
    assert_redirected_to organizers_tournament_templates_path
    assert TournamentTemplate.last.format_biggest_vs_smallest?
  end

  test "create accepts format: fish_train with train_cars and pool" do
    perch = create(:species, club: @club, name: "Perch")
    pike  = create(:species, club: @club, name: "Pike")
    assert_difference -> { TournamentTemplate.count }, 1 do
      post organizers_tournament_templates_path, params: {
        tournament_template: {
          name: "FT Monthly", mode: "solo", format: "fish_train",
          train_cars: [perch.id.to_s, pike.id.to_s, perch.id.to_s],
          tournament_template_scoring_slots_attributes: {
            "0" => { species_id: perch.id, slot_count: 1 },
            "1" => { species_id: pike.id,  slot_count: 1 }
          }
        }
      }
    end
    assert_redirected_to organizers_tournament_templates_path
    created = TournamentTemplate.last
    assert created.format_fish_train?
    assert_equal [perch.id, pike.id, perch.id], created.train_cars
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
