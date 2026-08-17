require "test_helper"

class Organizers::LeagueNightsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @member = create(:user, club: @club, role: :member)
    @walleye = create(:species, name: "Walleye")
    @main = create(:tournament_template, club: @club, name: "League Night - Main", mode: :team,
                   default_weekday: 3, default_start_time: "18:00", default_end_time: "21:00",
                   blind_leaderboard: true)
    @side = create(:tournament_template, club: @club, name: "League Night - Side", mode: :team,
                   default_weekday: 3, default_start_time: "18:00", default_end_time: "21:00")
    @main.update!(paired_template: @side)
    sign_in_as(@organizer)
  end

  test "the screen prefills the next occurrence and names both columns" do
    get new_organizers_tournament_template_league_night_path(tournament_template_id: @main.id)
    assert_response :success
    assert_match(/League Night - Main/, response.body)
    assert_match(/League Night - Side/, response.body)
  end

  test "solo-only and excluded formats are not offered" do
    get new_organizers_tournament_template_league_night_path(tournament_template_id: @main.id)
    assert_no_match(/Big Fish Season/, response.body)
    assert_no_match(/Tagged Walleye/, response.body)
    assert_no_match(/Fish Train/, response.body)
    assert_no_match(/>Bingo</, response.body)
    # By enum key too: the label assertions above can't catch an excluded format
    # that slipped in under a different label.
    %w[big_fish_season tagged fish_train bingo].each do |key|
      assert_no_match(/value="#{key}"/, response.body)
    end
  end

  # The formats that ARE offered have to read the way they do everywhere else in
  # the app — titleizing the enum keys would say "Beat The Average" here and
  # "Catch the Average" on the tournament form.
  test "offered formats use the app's own format labels" do
    get new_organizers_tournament_template_league_night_path(tournament_template_id: @main.id)
    assert_match(/>Catch the Average</, response.body)
    assert_no_match(/Beat The Average/, response.body)
  end

  test "an unpaired template can't be scheduled as a league night" do
    solo = create(:tournament_template, club: @club, name: "Saturday", mode: :team)
    get new_organizers_tournament_template_league_night_path(tournament_template_id: solo.id)
    assert_redirected_to organizers_tournament_templates_path
    assert_equal "That template isn't paired with another one.", flash[:alert]
  end

  # A pair with no weekday/times has no next occurrence, so there is nothing to
  # prefill. The screen has to say so rather than render a form whose blank date
  # fields fail deep in the model on submit.
  test "a pair with no weekday or times says so instead of rendering the form" do
    unscheduled_main = create(:tournament_template, club: @club, name: "Someday - Main", mode: :team)
    unscheduled_side = create(:tournament_template, club: @club, name: "Someday - Side", mode: :team)
    unscheduled_main.update!(paired_template: unscheduled_side)

    get new_organizers_tournament_template_league_night_path(tournament_template_id: unscheduled_main.id)
    assert_response :success
    assert_match(/weekday/i, response.body)
    assert_no_match(/Create both/, response.body)
  end

  test "creating a league night makes both tournaments, linked" do
    starts_at, ends_at = @main.next_occurrence_at

    assert_difference "Tournament.count", 2 do
      post organizers_tournament_template_league_night_path(tournament_template_id: @main.id),
           params: { league_night: {
             starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
             main: { format: "pro_walleye", species_id: @walleye.id },
             side: { format: "smallest_fish", species_id: @walleye.id, slot_count: 1 }
           } }
    end

    main_t = Tournament.find_by(template_source_id: @main.id)
    side_t = Tournament.find_by(template_source_id: @side.id)
    assert_equal main_t.link_group_id, side_t.link_group_id
    assert_redirected_to edit_organizers_tournament_path(main_t)
  end

  # Main is always blind; the same-species leak warning on the Side column rests
  # on that. A crafted POST must not be able to un-blind it.
  test "a crafted blind_leaderboard on the main column is ignored" do
    starts_at, ends_at = @main.next_occurrence_at

    post organizers_tournament_template_league_night_path(tournament_template_id: @main.id),
         params: { league_night: {
           starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
           main: { format: "standard", species_id: @walleye.id, blind_leaderboard: "0" },
           side: { format: "standard", species_id: @walleye.id }
         } }

    assert Tournament.find_by(template_source_id: @main.id).blind_leaderboard?
  end

  test "a validation failure creates neither and re-renders" do
    starts_at, ends_at = @main.next_occurrence_at

    assert_no_difference "Tournament.count" do
      post organizers_tournament_template_league_night_path(tournament_template_id: @main.id),
           params: { league_night: {
             starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
             main: { format: "pro_walleye", species_id: @walleye.id },
             side: { format: "smallest_fish", species_id: "" }
           } }
    end
    assert_response :unprocessable_entity
  end

  test "an already-scheduled week is refused" do
    starts_at, ends_at = @main.next_occurrence_at
    create(:tournament, club: @club, mode: :team, starts_at: starts_at, ends_at: ends_at,
           template_source_id: @main.id)
    create(:tournament, club: @club, mode: :team, starts_at: starts_at, ends_at: ends_at,
           template_source_id: @side.id)

    assert_no_difference "Tournament.count" do
      post organizers_tournament_template_league_night_path(tournament_template_id: @main.id),
           params: { league_night: {
             starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
             main: { format: "standard", species_id: @walleye.id },
             side: { format: "standard", species_id: @walleye.id }
           } }
    end
    assert_match(/already scheduled/i, flash[:alert])
  end

  test "members are forbidden" do
    sign_in_as(@member)
    get new_organizers_tournament_template_league_night_path(tournament_template_id: @main.id)
    assert_response :forbidden
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
