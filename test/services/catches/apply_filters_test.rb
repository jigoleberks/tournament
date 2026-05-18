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

  test "wind_speed calm matches < 5" do
    calm  = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_speed_kph: 3)
    light = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_speed_kph: 5)
    result = call(wind_speed: "calm")
    assert_includes result, calm
    refute_includes result, light
  end

  test "wind_speed light matches 5..15 inclusive" do
    light_lo = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_speed_kph: 5)
    light_hi = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_speed_kph: 15)
    over     = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_speed_kph: 16)
    result = call(wind_speed: "light")
    assert_includes result, light_lo
    assert_includes result, light_hi
    refute_includes result, over
  end

  test "wind_speed mod matches >15 and <=25" do
    just_over_15 = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_speed_kph: 15.5)
    twenty_five  = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_speed_kph: 25)
    fifteen      = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_speed_kph: 15)
    result = call(wind_speed: "mod")
    assert_includes result, just_over_15
    assert_includes result, twenty_five
    refute_includes result, fifteen
  end

  test "wind_speed strong matches > 25" do
    strong = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_speed_kph: 30)
    edge   = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_speed_kph: 25)
    result = call(wind_speed: "strong")
    assert_includes result, strong
    refute_includes result, edge
  end

  test "pressure low matches < 1010" do
    low = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, barometric_pressure_hpa: 1005)
    norm = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, barometric_pressure_hpa: 1010)
    result = call(pressure: "low")
    assert_includes result, low
    refute_includes result, norm
  end

  test "pressure normal matches 1010..1020 inclusive" do
    n1 = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, barometric_pressure_hpa: 1010)
    n2 = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, barometric_pressure_hpa: 1020)
    high = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, barometric_pressure_hpa: 1021)
    result = call(pressure: "normal")
    assert_includes result, n1
    assert_includes result, n2
    refute_includes result, high
  end

  test "pressure high matches > 1020" do
    high = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, barometric_pressure_hpa: 1025)
    edge = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, barometric_pressure_hpa: 1020)
    result = call(pressure: "high")
    assert_includes result, high
    refute_includes result, edge
  end

  test "wind_speed/pressure: NULL columns excluded when filter active" do
    nilled = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, wind_speed_kph: nil, barometric_pressure_hpa: nil)
    refute_includes call(wind_speed: "calm"), nilled
    refute_includes call(pressure: "low"),    nilled
  end

  test "moon q1 matches 0.125..<0.375" do
    inside  = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, moon_phase_fraction: 0.25)
    edge_lo = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, moon_phase_fraction: 0.125)
    edge_hi = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, moon_phase_fraction: 0.375)
    result = call(moon: "q1")
    assert_includes result, inside
    assert_includes result, edge_lo
    refute_includes result, edge_hi  # exclusive top
  end

  test "moon full matches 0.375..<0.625" do
    inside = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, moon_phase_fraction: 0.5)
    result = call(moon: "full")
    assert_includes result, inside
  end

  test "moon new wraps across 0/1" do
    early = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, moon_phase_fraction: 0.05)
    late  = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, moon_phase_fraction: 0.95)
    mid   = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, moon_phase_fraction: 0.5)
    result = call(moon: "new")
    assert_includes result, early
    assert_includes result, late
    refute_includes result, mid
  end

  test "moon: NULL fraction excluded when filter active" do
    nilled = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 1.day.ago, moon_phase_fraction: nil)
    refute_includes call(moon: "full"), nilled
  end

  test "tod dawn matches 4..6" do
    five  = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2025, 5, 10, 5, 30))
    seven = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2025, 5, 10, 7, 0))
    result = call(tod: "dawn")
    assert_includes result, five
    refute_includes result, seven
  end

  test "tod noon matches 11..13" do
    eleven   = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2025, 5, 10, 11, 0))
    thirteen = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2025, 5, 10, 13, 59))
    fourteen = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2025, 5, 10, 14, 0))
    result = call(tod: "noon")
    assert_includes result, eleven
    assert_includes result, thirteen
    refute_includes result, fourteen
  end

  test "tod night wraps across midnight (23..3)" do
    eleven_pm = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2025, 5, 10, 23, 30))
    two_am    = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2025, 5, 11,  2, 0))
    five_am   = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: Time.zone.local(2025, 5, 10,  5, 0))
    result = call(tod: "night")
    assert_includes result, eleven_pm
    assert_includes result, two_am
    refute_includes result, five_am
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
