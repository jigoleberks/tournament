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
    starts_at, ends_at = @main.next_occurrence_at

    get new_organizers_tournament_template_league_night_path(tournament_template_id: @main.id)
    assert_response :success
    assert_match(/League Night - Main/, response.body)
    assert_match(/League Night - Side/, response.body)
    assert_select "input[name='league_night[starts_at]'][value=?]", starts_at.strftime("%Y-%m-%dT%H:%M")
    assert_select "input[name='league_night[ends_at]'][value=?]", ends_at.strftime("%Y-%m-%dT%H:%M")
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

  # This screen is the authority for the Side column's blind flag each week, so
  # the control has to be able to say "off" as well as "on". A bare check_box_tag
  # submits nothing at all when unchecked, and LeagueNights::Schedule then falls
  # back to the template's own flag — so unchecking the box would be a silent
  # no-op for a Side template that has blind_leaderboard set.
  test "unchecking the side blind box turns the flag off even when the template has it on" do
    @side.update!(blind_leaderboard: true)
    starts_at, ends_at = @main.next_occurrence_at

    get new_organizers_tournament_template_league_night_path(tournament_template_id: @main.id)

    # Reproduce exactly what a browser submits with that box unchecked: every
    # input under the name EXCEPT the checkbox itself (i.e. the companion hidden
    # field, if there is one).
    unchecked_value = css_select("input[name='league_night[side][blind_leaderboard]']")
                        .reject { |input| input["type"] == "checkbox" }
                        .map { |input| input["value"] }
                        .last
    side = { format: "standard", species_id: @walleye.id }
    side[:blind_leaderboard] = unchecked_value unless unchecked_value.nil?

    post organizers_tournament_template_league_night_path(tournament_template_id: @main.id),
         params: { league_night: {
           starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
           main: { format: "standard", species_id: @walleye.id },
           side: side
         } }

    assert_not Tournament.find_by(template_source_id: @side.id).blind_leaderboard?
  end

  # The other half of the same finding: the box's rendered state has to be its
  # effective state, or it reports the wrong thing before anyone touches it.
  test "the side blind box renders checked when the side template is blind" do
    @side.update!(blind_leaderboard: true)
    get new_organizers_tournament_template_league_night_path(tournament_template_id: @main.id)
    assert_select "input[type=checkbox][name='league_night[side][blind_leaderboard]'][checked]"
  end

  # The companion hidden field must stay out of the checkbox's way: no duplicate
  # id, and the sideBlind Stimulus target still on the checkbox itself.
  test "the side blind hidden field doesn't collide with the checkbox" do
    get new_organizers_tournament_template_league_night_path(tournament_template_id: @main.id)
    assert_select "input[type=hidden][name='league_night[side][blind_leaderboard]'][value='0']:not([id])", 1
    assert_select "#league_night_side_blind_leaderboard", 1
    assert_select "input[type=checkbox]#league_night_side_blind_leaderboard[data-league-night-target='sideBlind']", 1
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

  # 2026-08-06 really happened: the Main was created and its Side never was. The
  # scheduler has to be able to build the missing half without duplicating — or
  # disturbing — the one that already ran.
  test "a half-scheduled night offers to create the missing half only" do
    starts_at, ends_at = @main.next_occurrence_at
    existing = create(:tournament, club: @club, name: @main.name, mode: :team,
                      starts_at: starts_at, ends_at: ends_at, template_source_id: @main.id)

    get new_organizers_tournament_template_league_night_path(tournament_template_id: @main.id)
    assert_response :success
    assert_match(/already has .*League Night - Main/i, response.body)
    # Only the missing column is offered, and the button says what it will do —
    # "Create both" would be a lie here.
    assert_select "select[name='league_night[side][format]']", 1
    assert_select "select[name='league_night[main][format]']", 0
    assert_select "input[type=submit][value='Create the missing half']"
    assert_no_match(/Create both/, response.body)

    assert_difference "Tournament.count", 1 do
      post organizers_tournament_template_league_night_path(tournament_template_id: @main.id),
           params: { league_night: {
             starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
             side: { format: "standard", species_id: @walleye.id, slot_count: 1 }
           } }
    end

    side_t = Tournament.find_by(template_source_id: @side.id)
    assert_not_nil side_t
    assert_equal "League Night - Side", side_t.name
    assert_redirected_to edit_organizers_tournament_path(side_t)
    assert_equal existing.id, Tournament.find_by(template_source_id: @main.id).id
  end

  # The mirror image of the above: whichever half is missing is the one built.
  test "a half-scheduled night missing the main builds the main" do
    starts_at, ends_at = @main.next_occurrence_at
    create(:tournament, club: @club, name: @side.name, mode: :team,
           starts_at: starts_at, ends_at: ends_at, template_source_id: @side.id)

    get new_organizers_tournament_template_league_night_path(tournament_template_id: @main.id)
    assert_response :success
    assert_match(/already has .*League Night - Side/i, response.body)
    assert_select "select[name='league_night[main][format]']", 1
    assert_select "select[name='league_night[side][format]']", 0

    assert_difference "Tournament.count", 1 do
      post organizers_tournament_template_league_night_path(tournament_template_id: @main.id),
           params: { league_night: {
             starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
             main: { format: "standard", species_id: @walleye.id, slot_count: 1 }
           } }
    end

    main_t = Tournament.find_by(template_source_id: @main.id)
    assert_not_nil main_t
    assert_redirected_to edit_organizers_tournament_path(main_t)
  end

  # The excluded-format list was a picker affordance only: nothing stopped a
  # hand-rolled POST from naming a format the screen never offered. Bingo can
  # genuinely save here (all three card species exist, and the Side column isn't
  # blind), so without the check this really does create the league night the
  # exclusion exists to prevent.
  test "a format outside the schedulable list is refused" do
    create(:species, name: Species::PERCH_NAME)
    create(:species, name: Species::PIKE_NAME)
    starts_at, ends_at = @main.next_occurrence_at

    assert_no_difference "Tournament.count" do
      post organizers_tournament_template_league_night_path(tournament_template_id: @main.id),
           params: { league_night: {
             starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
             main: { format: "standard", species_id: @walleye.id },
             side: { format: "bingo", species_id: @walleye.id }
           } }
    end
    assert_response :unprocessable_entity
    assert_match(/isn&#39;t a format a league night can use/, response.body)
  end

  # An unknown key never reaches a validation at all — the enum setter raises
  # ArgumentError, which the RecordInvalid rescue doesn't catch, so this 500s
  # unless it's turned away first.
  test "an unknown format is refused instead of raising" do
    starts_at, ends_at = @main.next_occurrence_at

    assert_no_difference "Tournament.count" do
      post organizers_tournament_template_league_night_path(tournament_template_id: @main.id),
           params: { league_night: {
             starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
             main: { format: "nonsense", species_id: @walleye.id },
             side: { format: "standard", species_id: @walleye.id }
           } }
    end
    assert_response :unprocessable_entity
  end

  # And the same check on the repair path, which submits only one column and so
  # runs through a different set of arguments. Bingo again, for the same reason:
  # it is the one excluded format that would otherwise save cleanly here.
  test "an excluded format is refused when repairing a half-scheduled night" do
    create(:species, name: Species::PERCH_NAME)
    create(:species, name: Species::PIKE_NAME)
    starts_at, ends_at = @main.next_occurrence_at
    create(:tournament, club: @club, name: @main.name, mode: :team,
           starts_at: starts_at, ends_at: ends_at, template_source_id: @main.id)

    assert_no_difference "Tournament.count" do
      post organizers_tournament_template_league_night_path(tournament_template_id: @main.id),
           params: { league_night: {
             starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
             side: { format: "bingo", species_id: @walleye.id }
           } }
    end
    assert_response :unprocessable_entity
  end

  # LeagueNights::Schedule only mints a link_group_id when it builds a pair, so
  # the repaired half comes out unlinked — no shared roster, no shared boats,
  # which is the whole point of a league-night pair.
  test "repairing a half-scheduled night links it to the tournament that exists" do
    starts_at, ends_at = @main.next_occurrence_at
    existing = create(:tournament, club: @club, name: @main.name, mode: :team,
                      starts_at: starts_at, ends_at: ends_at, template_source_id: @main.id)
    entry = create(:tournament_entry, tournament: existing, name: "Team Walleye")
    create(:tournament_entry_member, tournament_entry: entry, user: @member)

    post organizers_tournament_template_league_night_path(tournament_template_id: @main.id),
         params: { league_night: {
           starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
           side: { format: "standard", species_id: @walleye.id, slot_count: 1 }
         } }

    side_t = Tournament.find_by(template_source_id: @side.id)
    assert side_t.link_group_id.present?
    assert_equal existing.reload.link_group_id, side_t.link_group_id
    # And the roster that already existed is mirrored onto the new half.
    assert_equal 1, side_t.tournament_entries.count
    counterpart = side_t.tournament_entries.first
    assert_equal "Team Walleye", counterpart.name
    assert_equal [@member.id], counterpart.tournament_entry_members.pluck(:user_id)
  end

  # A repair back-fills a roster for a night that may already be over, and
  # DeliverPushNotificationJob has no started/ended guard — so an un-suppressed
  # sync would tell every angler who fished the Main that they've "been entered
  # into" the Side of a tournament that finished days ago.
  test "repairing a half-scheduled night sends no push notifications" do
    starts_at, ends_at = @main.next_occurrence_at
    existing = create(:tournament, club: @club, name: @main.name, mode: :team,
                      starts_at: starts_at, ends_at: ends_at, template_source_id: @main.id)
    entry = create(:tournament_entry, tournament: existing, name: "Team Walleye")
    create(:tournament_entry_member, tournament_entry: entry, user: @member)

    assert_no_enqueued_jobs only: DeliverPushNotificationJob do
      post organizers_tournament_template_league_night_path(tournament_template_id: @main.id),
           params: { league_night: {
             starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
             side: { format: "standard", species_id: @walleye.id, slot_count: 1 }
           } }
    end
    # The sync really did run — otherwise this proves nothing.
    assert_equal 1, Tournament.find_by(template_source_id: @side.id).tournament_entries.count
  end

  # Re-rendering a pristine form throws away every choice the operator just made
  # and hands back only the error text. Every control the form carries is
  # asserted here — the Side blind box especially, whose fallback is the only
  # one with real logic (key-presence, not value-presence).
  test "a failed submit re-renders with the operator's own choices" do
    perch = create(:species, name: "Perch")
    @side.update!(blind_leaderboard: true)
    starts_at, ends_at = @main.next_occurrence_at
    moved_start = starts_at + 1.hour
    moved_end = ends_at + 1.hour

    post organizers_tournament_template_league_night_path(tournament_template_id: @main.id),
         params: { league_night: {
           starts_at: moved_start.iso8601, ends_at: moved_end.iso8601,
           main: { format: "random_bag", species_id: perch.id, slot_count: "4",
                   target_min_inches: "72.5", target_max_inches: "96.0" },
           side: { format: "standard", species_id: "", blind_leaderboard: "0" }
         } }

    assert_response :unprocessable_entity
    assert_select "input[name='league_night[starts_at]'][value=?]", moved_start.strftime("%Y-%m-%dT%H:%M")
    assert_select "input[name='league_night[ends_at]'][value=?]", moved_end.strftime("%Y-%m-%dT%H:%M")
    assert_select "select[name='league_night[main][format]'] option[value=?][selected]", "random_bag"
    assert_select "select[name='league_night[main][species_id]'] option[value=?][selected]", perch.id.to_s
    assert_select "input[name='league_night[main][slot_count]'][value='4']"
    assert_select "input[name='league_night[main][target_min_inches]'][value='72.5']"
    assert_select "input[name='league_night[main][target_max_inches]'][value='96.0']"
    # The Side template is blind, so falling back to it would come back checked.
    assert_select "input[type=checkbox][name='league_night[side][blind_leaderboard]'][checked]", 0
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
