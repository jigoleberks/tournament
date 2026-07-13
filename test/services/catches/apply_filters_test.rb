require "test_helper"

class Catches::ApplyFiltersTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @walleye = create(:species, club: @club, name: "Walleye")
    @perch   = create(:species, club: @club, name: "Perch")
  end

  def call(params)
    Catches::ApplyFilters.call(scope: Catch.where(user: @user), params: ActionController::Parameters.new(params))
  end

  # Walleye catch with the given condition attrs; used by the band tables below.
  def catch_with(**attrs)
    create(:catch, **{ user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago }.merge(attrs))
  end

  test "no params returns scope unchanged" do
    c = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago)
    assert_includes call({}), c
  end

  test "species filter narrows by species_id" do
    a = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago)
    b = create(:catch, user: @user, species: @perch,   length_inches: 10, captured_at_device: 1.day.ago)
    result = call(species: @walleye.id.to_s)
    assert_includes result, a
    refute_includes result, b
  end

  test "lake filter: known key matches stored lake" do
    a = create(:catch, user: @user, species: @walleye, length_inches: 18, lake: "boundary_dam", captured_at_device: 1.day.ago)
    b = create(:catch, user: @user, species: @walleye, length_inches: 18, lake: nil,            captured_at_device: 1.day.ago)
    result = call(lake: "boundary_dam")
    assert_includes result, a
    refute_includes result, b
  end

  test "lake filter: 'other' matches NULL lake" do
    a = create(:catch, user: @user, species: @walleye, length_inches: 18, lake: "boundary_dam", captured_at_device: 1.day.ago)
    b = create(:catch, user: @user, species: @walleye, length_inches: 18, lake: nil,            captured_at_device: 1.day.ago)
    result = call(lake: "other")
    refute_includes result, a
    assert_includes result, b
  end

  test "lake filter: unknown key is ignored" do
    a = create(:catch, user: @user, species: @walleye, length_inches: 18, lake: "boundary_dam", captured_at_device: 1.day.ago)
    result = call(lake: "neverland")
    assert_includes result, a
  end

  test "date range filter: start and end bound captured_at_device" do
    in_range  = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2026, 5, 10, 9))
    too_early = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2026, 5, 1,  9))
    too_late  = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2026, 5, 20, 9))
    result = call(start: "2026-05-05", end: "2026-05-15")
    assert_includes result, in_range
    refute_includes result, too_early
    refute_includes result, too_late
  end

  test "min_length excludes shorter catches" do
    short = create(:catch, user: @user, species: @walleye, length_inches: 12, captured_at_device: 1.day.ago)
    long  = create(:catch, user: @user, species: @walleye, length_inches: 22, captured_at_device: 1.day.ago)
    result = call(min_length: "18")
    refute_includes result, short
    assert_includes result, long
  end

  test "min_length boundary is inclusive" do
    exact = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago)
    result = call(min_length: "18")
    assert_includes result, exact
  end

  test "min_length: blank or zero is ignored" do
    short = create(:catch, user: @user, species: @walleye, length_inches: 12, captured_at_device: 1.day.ago)
    assert_includes call(min_length: ""),  short
    assert_includes call(min_length: "0"), short
  end

  test "month filter matches that month across years" do
    may_2024 = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2024, 5, 10, 9))
    may_2025 = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2025, 5, 10, 9))
    jun_2025 = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2025, 6, 10, 9))
    result = call(month: "5")
    assert_includes result, may_2024
    assert_includes result, may_2025
    refute_includes result, jun_2025
  end

  test "month filter overrides start/end date range" do
    may = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2024, 5, 10, 9))
    # date range would normally exclude 2024
    result = call(month: "5", start: "2026-01-01", end: "2026-12-31")
    assert_includes result, may
  end

  test "month filter ignores out-of-range values" do
    may = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2025, 5, 10, 9))
    assert_includes call(month: "0"),  may
    assert_includes call(month: "13"), may
    assert_includes call(month: ""),   may
  end

  test "month filter buckets late-evening catches by local time, not UTC" do
    # 10:30pm local on May 31. In UTC this is June 1 04:30. The correct
    # local month is May, so a `month: 5` filter must include this catch.
    late_may = create(:catch, user: @user, species: @walleye, length_inches: 18,
                              captured_at_device: Time.zone.local(2025, 5, 31, 22, 30))
    result = call(month: "5")
    assert_includes result, late_may
  end

  test "wind_dir NE matches [22.5, 67.5)" do
    inside  = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_direction_deg: 45)
    edge_lo = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_direction_deg: 22.5)
    edge_hi = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_direction_deg: 67.5)
    outside = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_direction_deg: 80)
    nilled  = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_direction_deg: nil)
    result = call(wind_dir: "ne")
    assert_includes result, inside
    assert_includes result, edge_lo
    refute_includes result, edge_hi  # 67.5 belongs to E (next cardinal)
    refute_includes result, outside
    refute_includes result, nilled
  end

  test "wind_dir N wraps across 0/360" do
    near_360 = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_direction_deg: 350)
    near_0   = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_direction_deg: 10)
    away     = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_direction_deg: 100)
    result = call(wind_dir: "n")
    assert_includes result, near_360
    assert_includes result, near_0
    refute_includes result, away
  end

  test "wind_dir boundary at 22.5 belongs to NE only, not N" do
    edge = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_direction_deg: 22.5)
    assert_includes call(wind_dir: "ne"), edge
    refute_includes call(wind_dir: "n"),  edge
  end

  test "wind_dir: unknown value ignored" do
    c = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_direction_deg: 45)
    assert_includes call(wind_dir: "up"), c
  end

  test "wind_speed bands select catches by kph range (boundaries inclusive/exclusive)" do
    bands = {
      "calm"   => { match: [3],        miss: [5] },
      "light"  => { match: [5, 15],    miss: [16] },
      "mod"    => { match: [15.5, 25], miss: [15] },
      "strong" => { match: [30],       miss: [25] }
    }
    bands.each do |band, spec|
      spec[:match].each do |kph|
        c = catch_with(wind_speed_kph: kph)
        assert_includes call(wind_speed: band), c, "#{band}: #{kph} kph should match"
      end
      spec[:miss].each do |kph|
        c = catch_with(wind_speed_kph: kph)
        refute_includes call(wind_speed: band), c, "#{band}: #{kph} kph should not match"
      end
    end
  end

  test "pressure bands select catches by hpa range (boundaries inclusive/exclusive)" do
    bands = {
      "low"    => { match: [1005],       miss: [1010] },
      "normal" => { match: [1010, 1020], miss: [1021] },
      "high"   => { match: [1025],       miss: [1020] }
    }
    bands.each do |band, spec|
      spec[:match].each do |hpa|
        c = catch_with(barometric_pressure_hpa: hpa)
        assert_includes call(pressure: band), c, "#{band}: #{hpa} hpa should match"
      end
      spec[:miss].each do |hpa|
        c = catch_with(barometric_pressure_hpa: hpa)
        refute_includes call(pressure: band), c, "#{band}: #{hpa} hpa should not match"
      end
    end
  end

  test "wind_speed/pressure: NULL columns excluded when filter active" do
    nilled = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_speed_kph: nil, barometric_pressure_hpa: nil)
    refute_includes call(wind_speed: "calm"), nilled
    refute_includes call(pressure: "low"),    nilled
  end

  test "moon bands select catches by phase fraction (q1 top-exclusive, new wraps 0/1)" do
    bands = {
      "q1"   => { match: [0.25, 0.125], miss: [0.375] }, # bottom inclusive, top exclusive
      "full" => { match: [0.5],         miss: [] },
      "new"  => { match: [0.05, 0.95],  miss: [0.5] }     # wraps across 0/1
    }
    bands.each do |band, spec|
      spec[:match].each do |frac|
        c = catch_with(moon_phase_fraction: frac)
        assert_includes call(moon: band), c, "#{band}: #{frac} should match"
      end
      spec[:miss].each do |frac|
        c = catch_with(moon_phase_fraction: frac)
        refute_includes call(moon: band), c, "#{band}: #{frac} should not match"
      end
    end
  end

  test "moon: NULL fraction excluded when filter active" do
    nilled = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, moon_phase_fraction: nil)
    refute_includes call(moon: "full"), nilled
  end

  test "tod bands select catches by hour-of-day range (night wraps midnight)" do
    at = ->(hour, min = 0, day = 10) { Time.zone.local(2025, 5, day, hour, min) }
    bands = {
      "dawn"  => { match: [at.(5, 30)],            miss: [at.(7)] },
      "noon"  => { match: [at.(11), at.(13, 59)],  miss: [at.(14)] },
      "night" => { match: [at.(23, 30), at.(2, 0, 11)], miss: [at.(5)] } # wraps across midnight
    }
    bands.each do |band, spec|
      spec[:match].each do |time|
        c = catch_with(captured_at_device: time)
        assert_includes call(tod: band), c, "#{band}: #{time} should match"
      end
      spec[:miss].each do |time|
        c = catch_with(captured_at_device: time)
        refute_includes call(tod: band), c, "#{band}: #{time} should not match"
      end
    end
  end

  test "active_filter_keys: empty when no condition params" do
    assert_empty Catches::ApplyFilters.active_filter_keys(ActionController::Parameters.new)
  end

  test "active_filter_keys: rejects invalid values that the service would silently ignore" do
    params = ActionController::Parameters.new(
      month: "13", wind_dir: "up", wind_speed: "hurricane",
      pressure: "very_low", moon: "halfmoon", tod: "afternoon"
    )
    assert_empty Catches::ApplyFilters.active_filter_keys(params)
  end

  test "active_filter_keys: returns the subset with valid values" do
    params = ActionController::Parameters.new(
      month: "5", wind_dir: "ne", moon: "halfmoon", pressure: "low", tod: "noon"
    )
    assert_equal %i[month wind_dir pressure tod], Catches::ApplyFilters.active_filter_keys(params)
  end

  test "parse_date: blank in, nil out" do
    assert_nil Catches::ApplyFilters.parse_date(nil)
    assert_nil Catches::ApplyFilters.parse_date("")
  end

  test "parse_date: unparseable strings return nil without raising" do
    assert_nil Catches::ApplyFilters.parse_date("banana")
  end

  test "parse_date: valid ISO date round-trips" do
    assert_equal Date.new(2026, 5, 17), Catches::ApplyFilters.parse_date("2026-05-17")
  end

  test "filters AND together: only catches matching every active filter survive" do
    match     = create(:catch, user: @user, species: @walleye, length_inches: 22,
                               captured_at_device: 1.day.ago,
                               wind_direction_deg: 45, moon_phase_fraction: 0.5)
    wrong_dir = create(:catch, user: @user, species: @walleye, length_inches: 22,
                               captured_at_device: 1.day.ago,
                               wind_direction_deg: 225, moon_phase_fraction: 0.5)
    wrong_moon = create(:catch, user: @user, species: @walleye, length_inches: 22,
                                captured_at_device: 1.day.ago,
                                wind_direction_deg: 45, moon_phase_fraction: 0.1)
    too_short = create(:catch, user: @user, species: @walleye, length_inches: 12,
                               captured_at_device: 1.day.ago,
                               wind_direction_deg: 45, moon_phase_fraction: 0.5)
    result = call(wind_dir: "ne", moon: "full", min_length: "18")
    assert_includes result, match
    refute_includes result, wrong_dir
    refute_includes result, wrong_moon
    refute_includes result, too_short
  end
end
