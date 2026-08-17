require "application_system_test_case"

class LeagueNightSchedulerTest < ApplicationSystemTestCase
  MAIN_COUNT = "[data-league-night-target='mainCountRow']".freeze
  SIDE_COUNT = "[data-league-night-target='sideCountRow']".freeze
  SIDE_RANGE = "[data-league-night-target='sideRangeRow']".freeze
  SIDE_BLIND = "[data-league-night-target='sideBlind']".freeze
  # How the controller locks a checkbox it is forcing on — the same idiom
  # tournament_format_controller uses. Deliberately not `disabled`, so the box
  # still submits its own "1" instead of leaning entirely on the model's
  # force_*_blind hooks.
  LOCKED = ".pointer-events-none.opacity-60".freeze

  setup do
    @club = create(:club, name: "Test Anglers")
    @organizer = create(:user, club: @club, role: :organizer, name: "Organizer One")
    # Species are global and the select lists them by name with nothing marked
    # selected, so BOTH columns land on Perch — which is exactly the matched
    # pair the leak warning exists for, and why the warning is expected to be
    # up the moment the screen loads.
    create(:species, name: "Perch")
    create(:species, name: "Walleye")
    @main = create(:tournament_template, club: @club, name: "League Night - Main", mode: :team,
                   default_weekday: 3, default_start_time: "18:00", default_end_time: "21:00",
                   blind_leaderboard: true)
    @side = create(:tournament_template, club: @club, name: "League Night - Side", mode: :team,
                   default_weekday: 3, default_start_time: "18:00", default_end_time: "21:00")
    @main.update!(paired_template: @side)

    token = SignInToken.issue!(user: @organizer)
    visit consume_session_path(token: token.token)
    visit_scheduler
  end

  test "the same-species warning tracks both species selects" do
    assert_text "reveals its standings"
    assert_text "Both nights score Perch"

    select "Walleye", from: "league_night[side][species_id]"
    assert_no_text "reveals its standings"

    select "Walleye", from: "league_night[main][species_id]"
    assert_text "Both nights score Walleye"
  end

  # Main is always blind, so the warning is about Side being the readable half.
  # A blind Side leaks nothing, whatever species it scores.
  test "a blind Side is not a leak" do
    assert_text "reveals its standings"

    check "league_night[side][blind_leaderboard]"
    assert_no_text "reveals its standings"

    uncheck "league_night[side][blind_leaderboard]"
    assert_text "reveals its standings"
  end

  # Nothing requires a paired template to be blind, and this screen never sets
  # Main's flag. With a non-blind Main there is no leak for a visible Side to
  # reveal, so the warning would be advice about a leak that doesn't exist —
  # and its effective state has to be recomputed as the Main format changes,
  # since a forced-blind format makes Main blind without a reload.
  test "the leak warning tracks whether Main is actually blind" do
    @main.update!(blind_leaderboard: false)
    visit_scheduler

    assert_no_text "reveals its standings"

    select "Catch the Average", from: "league_night[main][format]"
    assert_text "reveals its standings"

    select "Standard", from: "league_night[main][format]"
    assert_no_text "reveals its standings"
  end

  test "the slot-count field disappears for a format that pins the count" do
    assert_selector MAIN_COUNT, visible: true

    select "Pro Walleye", from: "league_night[main][format]"
    assert_selector MAIN_COUNT, visible: :hidden

    select "Progressive Length", from: "league_night[main][format]"
    assert_selector MAIN_COUNT, visible: :hidden

    select "Standard", from: "league_night[main][format]"
    assert_selector MAIN_COUNT, visible: true
  end

  # Each column is driven by its own format select — hiding Main's count row
  # must not take Side's with it.
  test "the two columns' count rows move independently" do
    select "Pro Walleye", from: "league_night[main][format]"
    assert_selector MAIN_COUNT, visible: :hidden
    assert_selector SIDE_COUNT, visible: true
  end

  test "the target-range fields appear only for Random Bag" do
    assert_selector SIDE_RANGE, visible: :hidden

    select "Random Bag", from: "league_night[side][format]"
    assert_selector SIDE_RANGE, visible: true

    select "Standard", from: "league_night[side][format]"
    assert_selector SIDE_RANGE, visible: :hidden
  end

  test "Side's blind box locks on for a format that forces blind, and unlocks after" do
    assert_selector "#{SIDE_BLIND}:not(:checked)"
    assert_no_selector "#{SIDE_BLIND}#{LOCKED}"

    select "Catch the Average", from: "league_night[side][format]"
    assert_selector "#{SIDE_BLIND}:checked"
    assert_selector "#{SIDE_BLIND}#{LOCKED}"
    # Locked, but never `disabled` — a disabled box submits nothing, which would
    # make Tournament's force_*_blind hooks the ONLY thing setting the flag.
    assert_no_selector "#{SIDE_BLIND}[disabled]"

    select "Random Bag", from: "league_night[side][format]"
    assert_selector "#{SIDE_BLIND}:checked"
    assert_selector "#{SIDE_BLIND}#{LOCKED}"
    assert_no_selector "#{SIDE_BLIND}[disabled]"

    # Back to a format that leaves blind up to the operator: the box unlocks and
    # goes back to the "off" it was rendered with, rather than keeping the tick
    # the forced format put there.
    select "Standard", from: "league_night[side][format]"
    assert_no_selector "#{SIDE_BLIND}#{LOCKED}"
    assert_selector "#{SIDE_BLIND}:not(:checked)"
  end

  # The Side template can itself be blind, in which case the box is rendered
  # already ticked. Passing through a forced-blind format must not be a way to
  # silently untick it.
  test "a Side that is blind by default keeps its tick after a forced-blind format" do
    @side.update!(blind_leaderboard: true)
    visit_scheduler

    assert_selector "#{SIDE_BLIND}:checked"
    assert_no_selector "#{SIDE_BLIND}#{LOCKED}"

    select "Catch the Average", from: "league_night[side][format]"
    assert_selector "#{SIDE_BLIND}#{LOCKED}"
    assert_selector "#{SIDE_BLIND}:checked"

    select "Standard", from: "league_night[side][format]"
    assert_no_selector "#{SIDE_BLIND}#{LOCKED}"
    assert_selector "#{SIDE_BLIND}:checked"
  end

  # A half-scheduled night renders ONE column, so half the controller's targets
  # are absent. An unguarded target read would raise on connect and take the
  # rest of the behaviour down with it — including the range rows, which ship
  # hidden and are only ever un-hidden by this controller.
  test "the repair path's single column still gets its behaviour" do
    starts_at, ends_at = @main.next_occurrence_at
    create(:tournament, club: @club, name: @main.name, mode: :team,
           template_source_id: @main.id, starts_at: starts_at, ends_at: ends_at)
    visit_scheduler

    assert_text "Only the missing half will be created."
    assert_no_selector MAIN_COUNT, visible: :all

    assert_selector SIDE_RANGE, visible: :hidden
    select "Random Bag", from: "league_night[side][format]"
    assert_selector SIDE_RANGE, visible: true

    select "Pro Walleye", from: "league_night[side][format]"
    assert_selector SIDE_COUNT, visible: :hidden
  end

  # The whole flow, from the pair's row on the templates index through to two
  # linked tournaments. Every other test here drives the scheduler screen
  # directly; this one is the only check that the row's button reaches it and
  # that #create's redirect lands somewhere that shows the pair.
  test "scheduling a league night from the templates index creates both, linked" do
    visit organizers_tournament_templates_path
    assert_text "League Night - Main + League Night - Side"
    click_button "Schedule next league night"

    select "Pro Walleye", from: "league_night[main][format]"
    select "Walleye", from: "league_night[main][species_id]"
    select "Smallest Fish", from: "league_night[side][format]"
    select "Perch", from: "league_night[side][species_id]"
    click_button "Create both"

    assert_text "League night scheduled."

    main_t = Tournament.find_by(template_source_id: @main.id)
    side_t = Tournament.find_by(template_source_id: @side.id)
    assert_not_nil main_t
    assert_not_nil side_t
    # Both being nil would satisfy the equality on its own, and an unlinked pair
    # is exactly the failure this test exists to catch.
    assert_not_nil main_t.link_group_id
    assert_equal main_t.link_group_id, side_t.link_group_id
    assert main_t.format_pro_walleye?
    assert side_t.format_smallest_fish?
    # The "Linked with" heading on the tournament edit page is unconditional, so
    # it only proves the redirect landed there. The blurb below it renders only
    # when the tournament actually has a linked partner.
    assert_text "Linked with"
    assert_text "Entries are shared. Adding a boat here adds it there."
  end

  private

  def visit_scheduler
    visit new_organizers_tournament_template_league_night_path(tournament_template_id: @main.id)
  end
end
