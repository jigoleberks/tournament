require "test_helper"

class LeagueNights::NextOccurrenceTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @main = create(:tournament_template, club: @club, name: "Main", mode: :team,
                   default_weekday: 3, default_start_time: "18:00", default_end_time: "21:00")
    @side = create(:tournament_template, club: @club, name: "Side", mode: :team,
                   default_weekday: 3, default_start_time: "18:00", default_end_time: "21:00")
    @main.update!(paired_template: @side)
  end

  test "resolves the next occurrence and both templates" do
    result = LeagueNights::NextOccurrence.call(template: @main)

    assert_equal @main, result.main_template
    assert_equal @side, result.side_template
    assert_equal 3, result.starts_at.wday
    assert_equal 18, result.starts_at.hour
    assert_equal 21, result.ends_at.hour
    assert_not result.fully_scheduled?
    assert_not result.partially_scheduled?
  end

  test "detects a night already scheduled from both templates" do
    starts_at, ends_at = @main.next_occurrence_at
    main_t = create(:tournament, club: @club, mode: :team, starts_at: starts_at, ends_at: ends_at,
                    template_source_id: @main.id)
    side_t = create(:tournament, club: @club, mode: :team, starts_at: starts_at, ends_at: ends_at,
                    template_source_id: @side.id)

    result = LeagueNights::NextOccurrence.call(template: @main)

    assert result.fully_scheduled?
    assert_equal main_t, result.existing_main
    assert_equal side_t, result.existing_side
  end

  # Without `on:` the screen can only ever look at a FUTURE night, so the
  # already-run half-night it exists to repair is unreachable.
  test "on: resolves the named date rather than rolling forward" do
    past = 3.weeks.ago.to_date

    result = LeagueNights::NextOccurrence.call(template: @main, on: past)

    assert_equal past, result.starts_at.to_date
    assert_equal past, result.ends_at.to_date
    assert_equal 18, result.starts_at.hour
    assert_equal 21, result.ends_at.hour
  end

  # The named date needn't be one of the template's own weekdays — 2026-08-06,
  # the night this exists for, was a Thursday against a Wednesday template.
  test "on: honours a date that isn't the template's weekday" do
    off_day = 3.weeks.ago.to_date
    off_day += 1.day while off_day.wday == @main.default_weekday

    result = LeagueNights::NextOccurrence.call(template: @main, on: off_day)

    assert_equal off_day, result.starts_at.to_date
    assert_not_equal @main.default_weekday, result.starts_at.wday
  end

  test "on: detects a half-scheduled night in the past" do
    past = 3.weeks.ago.to_date
    starts_at, ends_at = @main.occurrence_at(past)
    main_t = create(:tournament, club: @club, mode: :team, starts_at: starts_at, ends_at: ends_at,
                    template_source_id: @main.id)

    result = LeagueNights::NextOccurrence.call(template: @main, on: past)

    assert result.partially_scheduled?
    assert_equal main_t, result.existing_main
    assert_nil result.existing_side
    # And the same template with no date still sees an untouched future night.
    assert_not LeagueNights::NextOccurrence.call(template: @main).partially_scheduled?
  end

  test "on: still reports no window when the template has no weekday or times" do
    unscheduled = create(:tournament_template, club: @club, name: "Someday", mode: :team)

    result = LeagueNights::NextOccurrence.call(template: unscheduled, on: 3.weeks.ago.to_date)

    assert_nil result.starts_at
    assert_nil result.ends_at
  end

  test "detects a half-scheduled night" do
    starts_at, ends_at = @main.next_occurrence_at
    create(:tournament, club: @club, mode: :team, starts_at: starts_at, ends_at: ends_at,
           template_source_id: @main.id)

    result = LeagueNights::NextOccurrence.call(template: @main)

    assert result.partially_scheduled?
    assert_not result.fully_scheduled?
    assert_nil result.existing_side
  end
end
