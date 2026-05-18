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
end
