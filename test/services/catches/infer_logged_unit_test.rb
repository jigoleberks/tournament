require "test_helper"

class Catches::InferLoggedUnitTest < ActiveSupport::TestCase
  test "value on the quarter-inch grid is inches" do
    assert_equal "inches", Catches::InferLoggedUnit.call(length_inches: 18.5)
    assert_equal "inches", Catches::InferLoggedUnit.call(length_inches: 31.25)
    assert_equal "inches", Catches::InferLoggedUnit.call(length_inches: 20.0)
  end

  test "value off the quarter-inch grid is centimeters" do
    assert_equal "centimeters", Catches::InferLoggedUnit.call(length_inches: 6.99)
    assert_equal "centimeters", Catches::InferLoggedUnit.call(length_inches: 14.47)
    assert_equal "centimeters", Catches::InferLoggedUnit.call(length_inches: 21.65)
  end

  test "on-grid value with a cm-preferring user is centimeters" do
    assert_equal "centimeters",
      Catches::InferLoggedUnit.call(length_inches: 20.0, user_length_unit: "centimeters")
  end

  test "nil length defaults to inches" do
    assert_equal "inches", Catches::InferLoggedUnit.call(length_inches: nil)
  end
end
