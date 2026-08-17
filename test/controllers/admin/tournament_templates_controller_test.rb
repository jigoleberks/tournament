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

  test "a paired template shows once, with a league-night action instead of Schedule next" do
    main = create(:tournament_template, club: @club, name: "League Night - Main",
                  default_weekday: 3, default_start_time: "18:00", default_end_time: "21:00")
    side = create(:tournament_template, club: @club, name: "League Night - Side",
                  default_weekday: 3, default_start_time: "18:00", default_end_time: "21:00")
    main.update!(paired_template: side)

    get admin_tournament_templates_path

    assert_response :success
    assert_select "form[action=?]",
                  new_admin_tournament_template_league_night_path(tournament_template_id: main.id),
                  count: 1
    assert_match(/League Night - Main \+ League Night - Side/, response.body)
    assert_select "form[action=?]", clone_admin_tournament_template_path(main), count: 0
    assert_select "form[action=?]", clone_admin_tournament_template_path(side), count: 0
    assert_select "a[href=?]", edit_admin_tournament_template_path(main), count: 1
    assert_select "a[href=?]", edit_admin_tournament_template_path(side), count: 1
    assert_select "form[action=?]", admin_tournament_template_path(main), count: 1
    assert_select "form[action=?]", admin_tournament_template_path(side), count: 1
  end

  test "an unpaired template keeps its own Schedule next button" do
    solo = create(:tournament_template, club: @club, name: "Saturday LML",
                  default_weekday: 6, default_start_time: "08:00", default_end_time: "16:00")

    get admin_tournament_templates_path

    assert_select "form[action=?]", clone_admin_tournament_template_path(solo), count: 1
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
