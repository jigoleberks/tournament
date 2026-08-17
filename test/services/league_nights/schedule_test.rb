require "test_helper"

class LeagueNights::ScheduleTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @walleye = create(:species, name: "Walleye")
    @perch = create(:species, name: "Perch")
    @main_template = create(:tournament_template, club: @club, name: "League Night - Main",
                            mode: :team, season_tag: "2026", awards_season_points: true,
                            blind_leaderboard: true, entrants_only_leaderboard: true)
    @side_template = create(:tournament_template, club: @club, name: "League Night - Side",
                            mode: :team, season_tag: "2026", awards_season_points: false,
                            entrants_only_leaderboard: true)
    @main_template.update!(paired_template: @side_template)
    @starts_at = 3.days.from_now.change(hour: 18)
    @ends_at = @starts_at + 3.hours
  end

  def schedule(main_overrides = {}, side_overrides = {})
    LeagueNights::Schedule.call(
      main_template: @main_template, side_template: @side_template,
      starts_at: @starts_at, ends_at: @ends_at,
      main: { format: "pro_walleye", species_id: @walleye.id }.merge(main_overrides),
      side: { format: "smallest_fish", species_id: @perch.id, slot_count: 1 }.merge(side_overrides)
    )
  end

  test "creates both tournaments in one link group" do
    main, side = schedule

    assert_equal "League Night - Main", main.name
    assert_equal "League Night - Side", side.name
    assert main.link_group_id.present?
    assert_equal main.link_group_id, side.link_group_id
    assert_equal [side], main.linked_tournaments
  end

  test "inherits the settings the scheduler does not show" do
    main, side = schedule

    assert_equal "2026", main.season_tag
    assert main.awards_season_points
    assert_not side.awards_season_points
    assert main.blind_leaderboard
    assert main.entrants_only_leaderboard
    assert main.mode_team?
    assert_equal @main_template.id, main.template_source_id
    assert_equal @side_template.id, side.template_source_id
  end

  test "applies the week's format and species per column" do
    main, side = schedule

    assert main.format_pro_walleye?
    assert_equal [@walleye.id], main.scoring_slots.map(&:species_id)
    assert side.format_smallest_fish?
    assert_equal [@perch.id], side.scoring_slots.map(&:species_id)
    assert_equal 1, side.scoring_slots.sole.slot_count
  end

  test "creates neither when one side is invalid" do
    assert_no_difference "Tournament.count" do
      assert_raises(ActiveRecord::RecordInvalid) do
        schedule({}, { species_id: nil })
      end
    end
  end

  test "sets Side blind when asked" do
    _main, side = schedule({}, { blind_leaderboard: true })
    assert side.blind_leaderboard
  end

  test "a Random Bag column applies the submitted target range" do
    main, _side = schedule({ format: "random_bag", target_min_inches: "72.5", target_max_inches: "96.0" })

    assert main.format_random_bag?
    assert_equal 72.5, main.target_min_inches.to_f
    assert_equal 96.0, main.target_max_inches.to_f
  end

  # The scheduler's range inputs are hidden with a CSS class, not removed, so they
  # submit on EVERY format: pick Random Bag, clear "Target min", switch back to
  # Standard, and a blank target_min_inches arrives on a Standard column.
  # random_bag_range_valid returns early for a non-Random-Bag format, so an
  # explicit nil went straight past validation and tripped the NOT NULL
  # constraint — a 500 out of an ordinary sequence of clicks.
  test "a non-Random-Bag column keeps the column defaults when a blank range is submitted" do
    main, _side = schedule({ format: "standard", target_min_inches: "", target_max_inches: "100" })

    assert_equal 70.0, main.target_min_inches.to_f
    assert_equal 100.0, main.target_max_inches.to_f
  end

  # And a range that IS filled in is still ignored off Random Bag — the columns
  # mean nothing to any other format, so leaving them at the defaults keeps a
  # stale hidden value from being recorded as a real setting.
  test "a non-Random-Bag column ignores a filled-in target range" do
    main, _side = schedule({ format: "standard", target_min_inches: "72.5", target_max_inches: "96.0" })

    assert_equal 70.0, main.target_min_inches.to_f
    assert_equal 100.0, main.target_max_inches.to_f
  end

  # A Random Bag week with a blank range must still fail in validation, not fall
  # back to 70/100 behind the operator's back.
  test "a Random Bag column with a blank range is a validation failure" do
    error = assert_raises(ActiveRecord::RecordInvalid) do
      schedule({ format: "random_bag", target_min_inches: "" })
    end
    assert_match(/target range/i, error.message)
  end

  test "creates only the main tournament when there is no side template" do
    main = LeagueNights::Schedule.call(
      main_template: @main_template, side_template: nil,
      starts_at: @starts_at, ends_at: @ends_at,
      main: { format: "standard", species_id: @walleye.id, slot_count: 3 }, side: nil
    ).first

    assert_equal 1, Tournament.count
    assert_nil main.link_group_id
  end
end
