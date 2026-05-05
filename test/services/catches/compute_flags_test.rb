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

  test "possible_duplicate when same user has another catch within 90s" do
    now = Time.current
    create(:catch, user: @user, species: @walleye, captured_at_device: now - 30.seconds)
    catch_record = build(:catch, user: @user, species: @walleye, captured_at_device: now)
    assert_includes Catches::ComputeFlags.call(catch_record), "possible_duplicate"
  end

  test "possible_duplicate NOT set when nearest sibling is outside 90s window" do
    now = Time.current
    create(:catch, user: @user, species: @walleye, captured_at_device: now - 91.seconds)
    catch_record = build(:catch, user: @user, species: @walleye, captured_at_device: now)
    assert_not_includes Catches::ComputeFlags.call(catch_record), "possible_duplicate"
  end

  test "possible_duplicate NOT triggered by another user's nearby catch when not on the same team" do
    now = Time.current
    other = create(:user, club: @club)
    create(:catch, user: other, species: @walleye, captured_at_device: now - 30.seconds)
    catch_record = build(:catch, user: @user, species: @walleye, captured_at_device: now)
    assert_not_includes Catches::ComputeFlags.call(catch_record), "possible_duplicate"
  end

  test "possible_duplicate IS triggered by a teammate's nearby catch" do
    now = Time.current
    teammate = create(:user, club: @club)
    tournament = create(:tournament, club: @club, mode: :team,
                                      starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    entry = create(:tournament_entry, tournament: tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)
    create(:tournament_entry_member, tournament_entry: entry, user: teammate)
    create(:catch, user: teammate, species: @walleye, captured_at_device: now - 30.seconds)
    catch_record = build(:catch, user: @user, species: @walleye, captured_at_device: now)
    assert_includes Catches::ComputeFlags.call(catch_record), "possible_duplicate"
  end

  test "possible_duplicate NOT triggered by a former teammate (tournament already closed)" do
    now = Time.current
    former_teammate = create(:user, club: @club)
    tournament = create(:tournament, club: @club, mode: :team,
                                      starts_at: 2.days.ago, ends_at: 1.day.ago)
    entry = create(:tournament_entry, tournament: tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)
    create(:tournament_entry_member, tournament_entry: entry, user: former_teammate)
    create(:catch, user: former_teammate, species: @walleye, captured_at_device: now - 30.seconds)
    catch_record = build(:catch, user: @user, species: @walleye, captured_at_device: now)
    assert_not_includes Catches::ComputeFlags.call(catch_record), "possible_duplicate"
  end

  test "out_of_province set when GPS present but outside Saskatchewan" do
    catch_record = build(:catch, user: @user, species: @walleye,
                                  latitude: 49.9, longitude: -97.1) # Winnipeg
    assert_includes Catches::ComputeFlags.call(catch_record), "out_of_province"
  end

  test "out_of_province NOT set when GPS is inside Saskatchewan (out of lake)" do
    catch_record = build(:catch, user: @user, species: @walleye,
                                  latitude: 50.45, longitude: -104.61) # Regina
    assert_not_includes Catches::ComputeFlags.call(catch_record), "out_of_province"
  end

  test "out_of_province NOT set when GPS missing" do
    catch_record = build(:catch, user: @user, species: @walleye, latitude: nil, longitude: nil)
    assert_not_includes Catches::ComputeFlags.call(catch_record), "out_of_province"
  end

  test "out_of_bounds and out_of_province both set when catch is outside both polygons" do
    catch_record = build(:catch, user: @user, species: @walleye,
                                  latitude: 49.9, longitude: -97.1) # Winnipeg — out of lake AND out of Sask
    flags = Catches::ComputeFlags.call(catch_record)
    assert_includes flags, "out_of_bounds"
    assert_includes flags, "out_of_province"
  end
end
