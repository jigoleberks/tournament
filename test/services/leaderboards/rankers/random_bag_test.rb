require "test_helper"

module Leaderboards
  module Rankers
    class RandomBagTest < ActiveSupport::TestCase
      Entry = Struct.new(:id, :display_name)

      def entry_row(entry_id:, target:, catches: [])
        # catches: array of [catch_id, length, captured_at_device]
        fish = catches.map do |id, length, captured|
          { id: id, length_inches: BigDecimal(length.to_s), captured_at_device: captured,
            species_name: "Walleye", angler_name: "A#{entry_id}",
            logged_by_name: nil, approver_name: nil, length_unit: "inches" }
        end
        { entry: Entry.new(entry_id, "Entry #{entry_id}"),
          target: target && BigDecimal(target.to_s),
          fish: fish,
          earliest_catch_at: fish.map { |f| f[:captured_at_device] }.compact.min }
      end

      test "one row per entry with its best bag distance to its own target" do
        # Entry 1 target 80, has 40+41 = 81 (dist 1). Entry 2 target 60, has 30+31 = 61 (dist 1).
        a = entry_row(entry_id: 1, target: 80, catches: [[101, 40, 2.hours.ago], [102, 41, 1.hour.ago]])
        b = entry_row(entry_id: 2, target: 60, catches: [[201, 30, 90.minutes.ago], [202, 31, 1.hour.ago]])
        result = RandomBag.call([a, b])
        by_entry = result.index_by { |r| r[:entry].id }
        assert_equal BigDecimal("81"), by_entry[1][:total]
        assert_equal BigDecimal("1"), by_entry[1][:distance]
        assert_equal BigDecimal("1"), by_entry[2][:distance]
      end

      test "ranks closest distance first, then earliest catch" do
        # Both 1 off; entry 2's qualifying catch is earlier -> entry 2 first.
        a = entry_row(entry_id: 1, target: 80, catches: [[101, 81, 1.hour.ago]])
        b = entry_row(entry_id: 2, target: 50, catches: [[201, 49, 3.hours.ago]])
        result = RandomBag.call([a, b])
        assert_equal 2, result.first[:entry].id
      end

      test "distance-tie tiebreak uses the bag's earliest catch, not a throwaway non-bag catch" do
        # Both end 0.5 from target 80 via a single 80.5 fish.
        # Entry 1 also logged an early 10" throwaway that is NOT in its best bag;
        # its actual bag catch is the latest of the three. Entry 2's bag catch is
        # earlier than entry 1's bag catch. Ranking must favor entry 2 — the
        # throwaway's early time must not win the tie for entry 1.
        a = entry_row(entry_id: 1, target: 80,
                      catches: [[101, 10, 6.hours.ago], [102, 80.5, 1.hour.ago]])
        b = entry_row(entry_id: 2, target: 80,
                      catches: [[201, 80.5, 3.hours.ago]])
        result = RandomBag.call([a, b])
        assert_equal 2, result.first[:entry].id
      end

      test "entry with no fish sinks to the bottom with nil distance" do
        a = entry_row(entry_id: 1, target: 80, catches: [[101, 79, 1.hour.ago]])
        empty = entry_row(entry_id: 2, target: 80, catches: [])
        result = RandomBag.call([a, empty])
        assert_equal 1, result.first[:entry].id
        assert_nil result.last[:distance]
        assert_nil result.last[:total]
      end

      test "unassigned target (nil) also sinks to the bottom" do
        scored = entry_row(entry_id: 1, target: 80, catches: [[101, 79, 1.hour.ago]])
        pending = entry_row(entry_id: 2, target: nil, catches: [[201, 79, 1.hour.ago]])
        result = RandomBag.call([scored, pending])
        assert_equal 1, result.first[:entry].id
        assert_nil result.last[:distance]
      end
    end
  end
end
