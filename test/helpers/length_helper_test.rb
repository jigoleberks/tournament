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
end
