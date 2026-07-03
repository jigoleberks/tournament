require "test_helper"

# Unit test for the request-side length parser shared by the judge manual-
# override and the organizer/admin catch editor.
class LengthParamParsingTest < ActiveSupport::TestCase
  # Minimal host that mixes in the concern and exposes the private parser.
  class Host
    include LengthParamParsing
    attr_reader :params
    def initialize(params)
      @params = params
    end

    def parse
      resolved_length_inches
    end
  end

  def parse(params)
    Host.new(ActionController::Parameters.new(params)).parse
  end

  test "cm entry converts and rounds to the stored 2dp inch grid" do
    # 55 cm -> 55 / 2.54 = 21.6535..., but length_inches is decimal(5,2) = 21.65.
    # Rounding to 2dp here keeps a re-save of the prefilled value equal to the
    # stored value, so ApplyJudgeAction doesn't see a phantom length change.
    assert_equal 21.65, parse(length: "55", length_unit: "centimeters").to_f
  end

  test "cm entry snaps to the quarter-cm grid before converting" do
    # 50.1 cm snaps to 50.0 cm -> 50 / 2.54 = 19.685... -> 19.69 at 2dp.
    assert_equal 19.69, parse(length: "50.1", length_unit: "centimeters").to_f
  end

  test "inches entry stays on the quarter grid" do
    assert_equal 19.5, parse(length: "19.5", length_unit: "inches").to_f
  end

  test "legacy length_inches param passes through untouched" do
    assert_equal 18.25, parse(length_inches: "18.25").to_f
  end

  test "blank length yields nil" do
    assert_nil parse(length_unit: "inches")
  end
end
