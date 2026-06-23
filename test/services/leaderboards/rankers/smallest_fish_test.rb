require "test_helper"

module Leaderboards
  module Rankers
    class SmallestFishTest < ActiveSupport::TestCase
      Entry = Struct.new(:id, :display_name)

      # `catches` is an array of [catch_id, length, captured_at_device]
      def entry_row(entry_id:, catches: [], complete: false)
        fish = catches.map do |id, length, captured|
          {
            id: id,
            length_inches: length,
            captured_at_device: captured,
            species_name: "Walleye",
            angler_name: "Angler #{entry_id}",
            logged_by_name: nil,
            approver_name: nil
          }
        end
        {
          entry: Entry.new(entry_id, "Entry #{entry_id}"),
          total: fish.sum { |f| f[:length_inches] },
          fish: fish,
          fish_lengths: fish.map { |f| f[:length_inches] },
          earliest_catch_at: fish.map { |f| f[:captured_at_device] }.compact.min,
          complete: complete
        }
      end

      test "complete entries rank by total ascending (lowest sum wins)" do
        a = entry_row(entry_id: 1, catches: [[101, 10, 1.hour.ago], [102, 12, 30.minutes.ago]], complete: true) # 22
        b = entry_row(entry_id: 2, catches: [[201, 8, 45.minutes.ago], [202, 9, 30.minutes.ago]], complete: true) # 17

        result = SmallestFish.call([a, b])

        assert_equal [2, 1], result.map { |r| r[:entry].id }, "lowest total (17) wins"
      end

      test "complete entries rank above incomplete even when incomplete sums lower" do
        complete   = entry_row(entry_id: 1, catches: [[101, 5, 1.hour.ago], [102, 6, 30.minutes.ago]], complete: true) # 11
        incomplete = entry_row(entry_id: 2, catches: [[201, 3, 30.minutes.ago]], complete: false) # 3, but only 1 fish

        result = SmallestFish.call([complete, incomplete])

        assert_equal [1, 2], result.map { |r| r[:entry].id }, "complete basket ranks first regardless of lower incomplete sum"
      end

      test "among incomplete entries, more fish ranks above fewer" do
        two = entry_row(entry_id: 1, catches: [[101, 9, 1.hour.ago], [102, 9, 30.minutes.ago]], complete: false) # 18, 2 fish
        one = entry_row(entry_id: 2, catches: [[201, 3, 30.minutes.ago]], complete: false) # 3, 1 fish

        result = SmallestFish.call([two, one])

        assert_equal [1, 2], result.map { |r| r[:entry].id }, "2-fish incomplete ranks above 1-fish incomplete despite higher sum"
      end

      test "equal-size complete tie broken by per-fish ascending (smallest single fish wins)" do
        # Both total 20, both complete. A's smallest is 8, B's smallest is 9.
        a = entry_row(entry_id: 1, catches: [[101, 8, 1.hour.ago], [102, 12, 30.minutes.ago]], complete: true)
        b = entry_row(entry_id: 2, catches: [[201, 9, 45.minutes.ago], [202, 11, 30.minutes.ago]], complete: true)

        result = SmallestFish.call([a, b])

        assert_equal [1, 2], result.map { |r| r[:entry].id }, "smaller single fish (8 < 9) wins the per-fish tiebreak"
      end

      test "full tie broken by earliest captured_at_device then entry id" do
        same = 1.hour.ago
        a = entry_row(entry_id: 7, catches: [[101, 8, same], [102, 12, same]], complete: true)
        b = entry_row(entry_id: 3, catches: [[201, 8, same], [202, 12, same]], complete: true)

        result = SmallestFish.call([a, b])

        assert_equal [3, 7], result.map { |r| r[:entry].id }, "identical rows fall back to entry.id ascending"
      end
    end
  end
end
