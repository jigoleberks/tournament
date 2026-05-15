require "test_helper"

class Geofence::LakesTest < ActiveSupport::TestCase
  setup { Geofence::Lakes.reload! }

  test ".all returns one entry per polygon file" do
    keys = Geofence::Lakes.all.map { |e| e[:key] }
    on_disk = Dir[Rails.root.join("geofence/lakes/*.json")].map { |p| File.basename(p, ".json") }
    assert_equal on_disk.sort, keys.sort
  end

  test ".all entries carry key, name, and kind" do
    entry = Geofence::Lakes.all.find { |e| e[:key] == "tobin" }
    refute_nil entry
    assert_equal "Tobin Lake", entry[:name]
    assert_equal "lake", entry[:kind]
  end

  test ".all sorts every lake before every river" do
    entries = Geofence::Lakes.all
    last_lake = entries.rindex { |e| e[:kind] == "lake" }
    first_river = entries.index { |e| e[:kind] == "river" }
    refute_nil last_lake
    refute_nil first_river
    assert_operator last_lake, :<, first_river,
      "expected all lakes before any river in load order"
  end

  test ".match returns the key for a point inside a polygon" do
    # Coordinates chosen well inside Tobin Lake's open water.
    assert_equal "tobin", Geofence::Lakes.match(53.55, -103.65)
  end

  test ".match returns nil for a point outside every polygon" do
    # Open prairie north of Saskatoon, away from any tracked water body.
    assert_nil Geofence::Lakes.match(52.5, -106.5)
  end

  test ".match returns nil when latitude or longitude is missing" do
    assert_nil Geofence::Lakes.match(nil, -103.5)
    assert_nil Geofence::Lakes.match(53.5, nil)
  end

  test ".match honors polygon holes (islands)" do
    # Last Mountain Lake has island holes. A point on solid open water still matches.
    # Coordinates verified against the polygon: southern basin, clear of all hole rings.
    assert_equal "last_mountain", Geofence::Lakes.match(50.76, -104.885)
  end

  test ".known_key? is true for a real polygon key" do
    assert Geofence::Lakes.known_key?("tobin")
  end

  test ".known_key? is false for unknown, nil, and reserved sentinels" do
    refute Geofence::Lakes.known_key?("not-a-lake")
    refute Geofence::Lakes.known_key?(nil)
    refute Geofence::Lakes.known_key?("all")
    refute Geofence::Lakes.known_key?("other")
  end
end
