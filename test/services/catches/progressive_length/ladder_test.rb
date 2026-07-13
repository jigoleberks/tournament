require "test_helper"

module Catches
  module ProgressiveLength
    class LadderTest < ActiveSupport::TestCase
      # A stand-in for Catch: Ladder is pure and touches only these three readers,
      # so the unit test needs no database.
      Fish = Struct.new(:id, :length_inches, :captured_at_device)

      def fish(id, length, minutes_ago)
        Fish.new(id, BigDecimal(length.to_s), minutes_ago.minutes.ago)
      end

      test "empty set yields an empty ladder" do
        assert_equal [], Ladder.call([])
      end

      test "a single fish is one rung" do
        f = fish(1, 12, 90)
        assert_equal [f], Ladder.call([f])
      end

      test "each fish must strictly beat the previous rung" do
        a = fish(1, 12, 90)
        b = fish(2, 15, 80)
        c = fish(3, 18, 70)
        assert_equal [a, b, c], Ladder.call([a, b, c])
      end

      test "a smaller fish is a silent no-op and does not reset the ladder" do
        a = fish(1, 12, 90)
        small = fish(2, 9, 80)
        b = fish(3, 15, 70)
        assert_equal [a, b], Ladder.call([a, small, b])
      end

      test "an equal-length fish is a no-op" do
        a = fish(1, 12, 90)
        tie = fish(2, 12, 80)
        assert_equal [a], Ladder.call([a, tie])
      end

      test "a strictly descending run yields exactly one rung" do
        a = fish(1, 20, 90)
        b = fish(2, 18, 80)
        c = fish(3, 16, 70)
        assert_equal [a], Ladder.call([a, b, c])
      end

      test "ladder is derived in capture order, not argument order" do
        early = fish(1, 12, 90)
        late  = fish(2, 15, 70)
        # Passed late-first; capture order must still put `early` at rung 0.
        assert_equal [early, late], Ladder.call([late, early])
      end

      test "a late-arriving big fish captured early invalidates the rungs above it" do
        # Spec's worked example: 12@10:00, 15@11:00, 18@12:00 → 2 up-sizes.
        # A 20 captured between the 12 and the 15 collapses the ladder to 12→20.
        a  = fish(1, 12, 120)
        b  = fish(2, 15, 60)
        c  = fish(3, 18, 30)
        big = fish(4, 20, 90)
        assert_equal [a, big], Ladder.call([a, b, c, big])
      end

      test "equal capture timestamps are broken by id so the ladder is deterministic" do
        at = 90.minutes.ago
        a = Fish.new(1, BigDecimal("12"), at)
        b = Fish.new(2, BigDecimal("15"), at)
        assert_equal [a, b], Ladder.call([b, a])
      end

      test "sub-second capture order is respected despite later-syncing id" do
        # An earlier-captured fish (high id, synced late) vs later-captured fish (low id, synced first)
        # both within the same second. Sort key must use full timestamp precision.
        base = 90.minutes.ago
        base = base.change(usec: 0)  # Round to whole second
        early_but_late_synced = Fish.new(9, BigDecimal("12"), base + 0.1)
        later_but_synced_first = Fish.new(3, BigDecimal("15"), base + 0.9)

        # With .to_i (buggy), both have same truncated timestamp, so sort falls back to id.
        # id=3 < id=9, so order becomes [15", 12"], and ladder is [15"] (12" is no-op).
        # With correct sort (no .to_i), order is [12", 15"], and ladder is [12", 15"].
        # This test proves capture order is preserved despite inverted ids.
        expected = [early_but_late_synced, later_but_synced_first]
        assert_equal expected, Ladder.call([early_but_late_synced, later_but_synced_first])
        assert_equal expected, Ladder.call([later_but_synced_first, early_but_late_synced])
      end
    end
  end
end
