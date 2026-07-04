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

    def parse_for(catch)
      resolved_length_inches(catch)
    end
  end

  def parse(params)
    Host.new(ActionController::Parameters.new(params)).parse
  end

  # Stands in for the catch the editor prefilled the form from.
  CatchStub = Struct.new(:length_inches, :length_unit)

  def parse_for(params, catch)
    Host.new(ActionController::Parameters.new(params)).parse_for(catch)
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

  test "an untouched prefilled cm value resolves to the stored inches, not a drifted one" do
    # Legacy inch-grid catch mis-tagged cm: stored 8.50", the editor prefills
    # display_cm(8.50, cm) = 21.5 cm. A note/species-only save resubmits 21.5
    # unchanged, so it must resolve back to 8.50 — not drift to 8.46, which
    # would trip a phantom length change and re-score every basket it's in.
    catch = CatchStub.new(BigDecimal("8.50"), "centimeters")
    assert_equal 8.50, parse_for({ length: "21.5", length_unit: "centimeters" }, catch).to_f
  end

  test "an untouched off-grid inches prefill resolves to the stored value" do
    # Stored 8.53" (off the 0.25 grid). Leaving the field alone must not snap
    # it to 8.50 on a note-only edit.
    catch = CatchStub.new(BigDecimal("8.53"), "inches")
    assert_equal 8.53, parse_for({ length: "8.53", length_unit: "inches" }, catch).to_f
  end

  test "a genuinely changed cm length still converts (guard fires only on the exact prefill)" do
    # Same mis-tagged catch, but the organizer actually remeasures to 55 cm.
    catch = CatchStub.new(BigDecimal("8.50"), "centimeters")
    assert_equal 21.65, parse_for({ length: "55", length_unit: "centimeters" }, catch).to_f
  end
end
