require "test_helper"

class ConditionsHelperTest < ActionView::TestCase
  test "format_wind_compass returns nil for nil" do
    assert_nil format_wind_compass(nil)
  end

  test "format_wind_compass maps cardinal points" do
    assert_equal "N",  format_wind_compass(0)
    assert_equal "NE", format_wind_compass(45)
    assert_equal "E",  format_wind_compass(90)
    assert_equal "SE", format_wind_compass(135)
    assert_equal "S",  format_wind_compass(180)
    assert_equal "SW", format_wind_compass(225)
    assert_equal "W",  format_wind_compass(270)
    assert_equal "NW", format_wind_compass(315)
  end

  test "format_wind_compass bin boundaries snap up at the midpoint" do
    # N covers [337.5, 22.5); NE covers [22.5, 67.5); etc.
    assert_equal "N",  format_wind_compass(22.4)
    assert_equal "NE", format_wind_compass(22.5)
    assert_equal "NE", format_wind_compass(67.4)
    assert_equal "E",  format_wind_compass(67.5)
  end

  test "format_wind_compass wraps around 360" do
    assert_equal "N", format_wind_compass(337.5)
    assert_equal "N", format_wind_compass(359.9)
    assert_equal "N", format_wind_compass(360)
  end

  test "format_wind_compass accepts decimals (Open-Meteo returns floats)" do
    assert_equal "NW", format_wind_compass(312.7)
  end

  test "format_pressure_trend returns nil for nil" do
    assert_nil format_pressure_trend(nil)
  end

  test "format_pressure_trend labels +/-2 hPa or more as rising/falling with kPa magnitude" do
    assert_equal "rising 0.4 kPa over 24h", format_pressure_trend(4.0)
    assert_equal "falling 0.3 kPa over 24h", format_pressure_trend(-3.0)
  end

  test "format_pressure_trend labels deltas inside the threshold as steady" do
    assert_equal "steady", format_pressure_trend(1.9)
    assert_equal "steady", format_pressure_trend(-1.9)
    assert_equal "steady", format_pressure_trend(0)
  end

  test "format_pressure_trend treats exactly +/-2 hPa as a meaningful change" do
    assert_equal "rising 0.2 kPa over 24h", format_pressure_trend(2.0)
    assert_equal "falling 0.2 kPa over 24h", format_pressure_trend(-2.0)
  end
end
