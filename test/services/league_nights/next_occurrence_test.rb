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
