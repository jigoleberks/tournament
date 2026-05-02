require "test_helper"

class Catches::ComputeFlagsTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @walleye = create(:species, club: @club)
  end

  test "no flags when GPS present, in-bounds, no clock skew" do
    catch_record = build(:catch, user: @user, species: @walleye,
                                  latitude: 49.41, longitude: -103.62,
                                  captured_at_device: Time.current,
                                  captured_at_gps: Time.current)
    assert_empty Catches::ComputeFlags.call(catch_record)
  end

  test "missing_gps when latitude nil" do
    catch_record = build(:catch, user: @user, species: @walleye, latitude: nil, longitude: nil)
    assert_includes Catches::ComputeFlags.call(catch_record), "missing_gps"
  end

  test "out_of_bounds when GPS present but outside polygon" do
    catch_record = build(:catch, user: @user, species: @walleye,
                                  latitude: 49.9, longitude: -97.1)
    assert_includes Catches::ComputeFlags.call(catch_record), "out_of_bounds"
  end

  test "out_of_bounds NOT set when GPS missing" do
    catch_record = build(:catch, user: @user, species: @walleye, latitude: nil, longitude: nil)
    assert_not_includes Catches::ComputeFlags.call(catch_record), "out_of_bounds"
  end

  test "clock_skew when device and GPS clocks diverge" do
    now = Time.current
    catch_record = build(:catch, user: @user, species: @walleye,
                                  latitude: 49.41, longitude: -103.62,
                                  captured_at_device: now,
                                  captured_at_gps: now - 10.minutes)
    assert_includes Catches::ComputeFlags.call(catch_record), "clock_skew"
  end
end
