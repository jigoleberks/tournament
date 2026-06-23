require "test_helper"

class LengthHelperTest < ActionView::TestCase
  test "inch-logged shows native inches trimmed and cm to 2 dp" do
    assert_equal "14.5\" / 36.83 cm", format_length_dual(14.5, "inches")
    assert_equal "22\" / 55.88 cm",   format_length_dual(22, "inches")
  end

  test "cm-logged shows inches to 2 dp and native cm snapped to the quarter grid" do
    assert_equal "14.47\" / 36.75 cm", format_length_dual(14.47, "centimeters")
    assert_equal "6.99\" / 17.75 cm",  format_length_dual(6.99, "centimeters")
    assert_equal "8.76\" / 22.25 cm",  format_length_dual(8.76, "centimeters")
    assert_equal "10.53\" / 26.75 cm", format_length_dual(10.53, "centimeters")
  end

  test "no unit (totals, targets) shows both to 2 dp" do
    assert_equal "22.00\" / 55.88 cm", format_length_dual(22)
  end

  test "nil length renders the dash" do
    assert_equal "—", format_length_dual(nil)
    assert_equal ["—", ""], format_length_parts(nil)
  end

  test "format_length_parts returns the two parts separately" do
    assert_equal ["14.47\"", "36.75 cm"], format_length_parts(14.47, "centimeters")
  end

  test "length_token is a filename-safe single token in the logged unit" do
    assert_equal "50 in", length_token(50, "inches")
    assert_equal "14.5 in", length_token(14.5, "inches")
    assert_equal "50 cm", length_token(19.69, "centimeters")
    assert_nil length_token(nil, "inches")
  end

  test "display_cm keeps cm-logged on the quarter grid but converts inch-logged exactly" do
    # 8.96 in -> 22.7584 cm: cm-logged snaps to 22.75; inch-logged shows raw.
    assert_equal 22.75, display_cm(8.96, "centimeters")
    assert_in_delta 22.76, display_cm(8.96, "inches"), 0.001
  end

  test "total_display_cm sums each fish's displayed cm (chip-consistent)" do
    # One cm-logged fish: total cm == that fish's snapped chip value, not the
    # drifted reconversion of the summed inches.
    one = [{ length_inches: 8.96, length_unit: "centimeters" }]
    assert_equal 22.75, total_display_cm(one)

    two = [
      { length_inches: 8.96, length_unit: "centimeters" },
      { length_inches: 15.0, length_unit: "inches" },
    ]
    assert_in_delta 22.75 + 38.10, total_display_cm(two), 0.001
  end

  test "total_display_cm is a spread for biggest_vs_smallest" do
    fish = [
      { length_inches: 20.0, length_unit: "centimeters" },  # biggest first
      { length_inches: 8.96, length_unit: "centimeters" },
    ]
    expected = display_cm(20.0, "centimeters") - display_cm(8.96, "centimeters")
    assert_equal expected, total_display_cm(fish, biggest_vs_smallest: true)
  end
end
