require "test_helper"

module Leaderboards
  module Rankers
    class ProgressiveLengthTest < ActiveSupport::TestCase
      Entry = Struct.new(:id)

      # fish are given in ladder order (smallest first), as build_rows produces.

      # One base instant for the whole test, so two fish given the same `mins`
      # get the SAME timestamp. Calling `mins.minutes.ago` per fish would make
      # nominally-equal times differ by wall-clock drift, which silently means
      # cascade level 2 (earliest final rung) always decides and level 3
      # (top rung desc) is never exercised.
      def base
        @base ||= Time.current
      end

      def row(entry_id, fish)
        {
          entry: Entry.new(entry_id),
          fish: fish.map { |len, mins| { length_inches: BigDecimal(len.to_s), captured_at_device: base - mins.minutes } }
        }
      end

      test "score is rungs minus one, clamped at zero" do
        ranked = ProgressiveLength.call([
          row(1, [[12, 90], [15, 80], [18, 70]]),
          row(2, [[20, 90]]),
          row(3, [])
        ])
        assert_equal [2, 0, 0], ranked.map { |r| r[:total] }
      end

      test "more up-sizes wins regardless of length" do
        ranked = ProgressiveLength.call([
          row(1, [[30, 90]]),                      # 0 up-sizes, huge fish
          row(2, [[8, 90], [9, 80], [10, 70]])     # 2 up-sizes, tiny fish
        ])
        assert_equal [2, 1], ranked.map { |r| r[:entry].id }
      end

      test "ties on up-sizes go to whoever reached the count first" do
        # Both have 1 up-size; entry 2's final rung was captured earlier.
        ranked = ProgressiveLength.call([
          row(1, [[12, 90], [15, 60]]),
          row(2, [[12, 90], [15, 70]])
        ])
        assert_equal [2, 1], ranked.map { |r| r[:entry].id }
      end

      test "same up-sizes and same final-rung time fall through to the taller ladder" do
        ranked = ProgressiveLength.call([
          row(1, [[12, 90], [15, 70]]),
          row(2, [[12, 90], [22, 70]])
        ])
        assert_equal [2, 1], ranked.map { |r| r[:entry].id }
      end

      test "a one-fish entry outranks a zero-fish entry despite both scoring 0" do
        ranked = ProgressiveLength.call([row(1, []), row(2, [[12, 90]])])
        assert_equal [2, 1], ranked.map { |r| r[:entry].id }
      end

      test "fully tied rows fall through to entry id" do
        ranked = ProgressiveLength.call([row(7, []), row(3, [])])
        assert_equal [3, 7], ranked.map { |r| r[:entry].id }
      end
    end
  end
end
