require "test_helper"

class GeofenceTest < ActiveSupport::TestCase
  test "lake: point inside the lake polygon returns true" do
    assert Geofence.includes?(:lake, 49.41, -103.62)
  end

  test "lake: point well outside the lake polygon returns false" do
    # Winnipeg
    assert_not Geofence.includes?(:lake, 49.9, -97.1)
  end

  test "sask: point inside Saskatchewan returns true" do
    # Regina
    assert Geofence.includes?(:sask, 50.45, -104.61)
  end

  test "sask: point in Manitoba returns false" do
    # Winnipeg
    assert_not Geofence.includes?(:sask, 49.9, -97.1)
  end

  test "sask: point in Alberta returns false" do
    # Calgary
    assert_not Geofence.includes?(:sask, 51.05, -114.07)
  end

  test "nil latitude returns false" do
    assert_not Geofence.includes?(:lake, nil, -103.5)
    assert_not Geofence.includes?(:sask, nil, -104.61)
  end

  test "nil longitude returns false" do
    assert_not Geofence.includes?(:lake, 49.45, nil)
    assert_not Geofence.includes?(:sask, 50.45, nil)
  end

  test "unknown region raises Geofence::UnknownRegion" do
    assert_raises(Geofence::UnknownRegion) do
      Geofence.includes?(:atlantis, 49.41, -103.62)
    end
  end

  test "reload! clears cached polygons" do
    Geofence.includes?(:lake, 49.41, -103.62) # warm cache
    Geofence.reload!
    # After reload, a subsequent call still works (re-loads from disk)
    assert Geofence.includes?(:lake, 49.41, -103.62)
  end
end
