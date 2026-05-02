require "test_helper"

class GeofenceTest < ActiveSupport::TestCase
  test "point inside the polygon returns true" do
    # Inside the polygon — midpoint of edge vertices 6 & 23 (reservoir is a thin diagonal)
    # 49.45, -103.5 (bounding-box centroid) lies outside the narrow shape
    assert Geofence.includes?(49.41, -103.62)
  end

  test "point well outside the polygon returns false" do
    # Winnipeg
    assert_not Geofence.includes?(49.9, -97.1)
  end

  test "nil latitude returns false" do
    assert_not Geofence.includes?(nil, -103.5)
  end

  test "nil longitude returns false" do
    assert_not Geofence.includes?(49.45, nil)
  end
end
