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
end
