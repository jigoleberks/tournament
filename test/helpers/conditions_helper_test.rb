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
end
