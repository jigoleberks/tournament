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

  test "create accepts season_tag" do
    assert_difference -> { TournamentTemplate.count }, 1 do
      post organizers_tournament_templates_path, params: {
        tournament_template: { name: "Wednesday League", mode: "solo", season_tag: "2026" }
      }
    end
    assert_redirected_to organizers_tournament_templates_path
    assert_equal "2026", TournamentTemplate.last.season_tag
  end

  test "POST clone carries the template's season_tag onto the tournament" do
    walleye = create(:species, club: @club)
    template = create(:tournament_template, club: @club, name: "Monthly Walleye", season_tag: "2026")
    template.tournament_template_scoring_slots.create!(species: walleye, slot_count: 1)

    post clone_organizers_tournament_template_path(template),
         params: { starts_at: 1.day.from_now, ends_at: 1.day.from_now + 4.hours }

    assert_equal "2026", Tournament.last.season_tag
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

  test "an organizer pairs two templates from the form" do
    main = create(:tournament_template, club: @club, name: "Wednesday Main")
    side = create(:tournament_template, club: @club, name: "Wednesday Side")

    patch organizers_tournament_template_path(main),
          params: { tournament_template: { name: main.name, paired_template_id: side.id } }

    assert_equal side, main.reload.paired_template
    assert_equal main, side.reload.paired_template
  end

  test "pairing with a template from another club is rejected" do
    main = create(:tournament_template, club: @club, name: "Wednesday Main")
    foreign = create(:tournament_template, club: create(:club))

    patch organizers_tournament_template_path(main),
          params: { tournament_template: { name: main.name, paired_template_id: foreign.id } }

    assert_nil main.reload.paired_template_id
  end

  test "a paired template shows once, with a league-night action instead of Schedule next" do
    main = create(:tournament_template, club: @club, name: "League Night - Main",
                  default_weekday: 3, default_start_time: "18:00", default_end_time: "21:00")
    side = create(:tournament_template, club: @club, name: "League Night - Side",
                  default_weekday: 3, default_start_time: "18:00", default_end_time: "21:00")
    main.update!(paired_template: side)

    get organizers_tournament_templates_path

    assert_response :success
    assert_select "form[action=?]",
                  new_organizers_tournament_template_league_night_path(tournament_template_id: main.id),
                  count: 1
    assert_match(/League Night - Main \+ League Night - Side/, response.body)
    assert_select "form[action=?]", clone_organizers_tournament_template_path(main), count: 0
    assert_select "form[action=?]", clone_organizers_tournament_template_path(side), count: 0
  end

  test "the paired row keeps an Edit link and a Delete button for each half" do
    main = create(:tournament_template, club: @club, name: "League Night - Main",
                  default_weekday: 3, default_start_time: "18:00", default_end_time: "21:00")
    side = create(:tournament_template, club: @club, name: "League Night - Side",
                  default_weekday: 3, default_start_time: "18:00", default_end_time: "21:00")
    main.update!(paired_template: side)

    get organizers_tournament_templates_path

    assert_select "a[href=?]", edit_organizers_tournament_template_path(main), count: 1
    assert_select "a[href=?]", edit_organizers_tournament_template_path(side), count: 1
    assert_select "form[action=?]", organizers_tournament_template_path(main), count: 1
    assert_select "form[action=?]", organizers_tournament_template_path(side), count: 1
  end

  test "an unpaired template keeps its own Schedule next button" do
    solo = create(:tournament_template, club: @club, name: "Saturday LML",
                  default_weekday: 6, default_start_time: "08:00", default_end_time: "16:00")

    get organizers_tournament_templates_path

    assert_select "form[action=?]", clone_organizers_tournament_template_path(solo), count: 1
    assert_select "form[action=?]",
                  new_organizers_tournament_template_league_night_path(tournament_template_id: solo.id),
                  count: 0
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
