require "test_helper"

module Leaderboards
  module Rankers
    class BiggestVsSmallestTest < ActiveSupport::TestCase
      Entry = Struct.new(:id, :display_name)

      def entry_row(entry_id:, catches: [])
        # `catches` is an array of [catch_id, length, captured_at_device]
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
          complete: false
        }
      end

      test "two-catch entries are ranked by spread descending" do
        a = entry_row(entry_id: 1, catches: [[101, 22, 1.hour.ago], [102, 12, 30.minutes.ago]])  # spread 10
        b = entry_row(entry_id: 2, catches: [[201, 18, 45.minutes.ago], [202, 14, 30.minutes.ago]]) # spread 4

        result = BiggestVsSmallest.call([a, b])

        assert_equal [1, 2], result.map { |r| r[:entry].id }
        assert_equal 10, result[0][:total]
        assert_equal 4,  result[1][:total]
      end

      test "single-catch entries score 0 and sort below all two-catch entries" do
        single = entry_row(entry_id: 1, catches: [[101, 30, 1.hour.ago]])  # giant fish but only 1
        small  = entry_row(entry_id: 2, catches: [[201, 13, 30.minutes.ago], [202, 12, 20.minutes.ago]]) # spread 1

        result = BiggestVsSmallest.call([single, small])

        # The single-catch entry has spread 0 and is incomplete; sorts below the 1" spread.
        assert_equal [2, 1], result.map { |r| r[:entry].id }
        assert_equal 1, result[0][:total]
        assert_equal 0, result[1][:total]
        assert_not result[1][:complete]
      end

      test "zero-catch entries sort last with nil total" do
        empty = entry_row(entry_id: 1, catches: [])
        any   = entry_row(entry_id: 2, catches: [[201, 18, 1.hour.ago], [202, 12, 30.minutes.ago]])

        result = BiggestVsSmallest.call([empty, any])

        assert_equal [2, 1], result.map { |r| r[:entry].id }
        assert_nil result[1][:total]
      end

      test "same-spread tie broken by earliest captured_at_device ascending" do
        # Both spreads are 6.
        # A's earliest catch: 2.hours.ago. B's earliest catch: 30.minutes.ago.
        a = entry_row(entry_id: 1, catches: [[101, 22, 2.hours.ago], [102, 16, 1.hour.ago]])
        b = entry_row(entry_id: 2, catches: [[201, 18, 30.minutes.ago], [202, 12, 25.minutes.ago]])

        result = BiggestVsSmallest.call([a, b])

        assert_equal [1, 2], result.map { |r| r[:entry].id }, "earlier earliest-catch wins the tie"
      end

      test "same-time tie broken by entry.id ascending" do
        same_time = 1.hour.ago
        a = entry_row(entry_id: 7, catches: [[101, 22, same_time], [102, 16, same_time]])
        b = entry_row(entry_id: 3, catches: [[201, 18, same_time], [202, 12, same_time]])

        result = BiggestVsSmallest.call([a, b])

        # Both spreads = 6, both earliest_catch_at = same_time → entry.id 3 wins.
        assert_equal [3, 7], result.map { |r| r[:entry].id }
      end

      test "row :fish is ordered biggest-first" do
        a = entry_row(entry_id: 1, catches: [[101, 12, 30.minutes.ago], [102, 22, 1.hour.ago]])

        result = BiggestVsSmallest.call([a])

        assert_equal 22, result.first[:fish].first[:length_inches], "biggest catch should be first in :fish"
        assert_equal 12, result.first[:fish].last[:length_inches],  "smallest catch should be last in :fish"
      end

      test "row :complete is true only for two-or-more catches" do
        zero  = entry_row(entry_id: 1, catches: [])
        one   = entry_row(entry_id: 2, catches: [[201, 18, 1.hour.ago]])
        two   = entry_row(entry_id: 3, catches: [[301, 18, 1.hour.ago], [302, 12, 30.minutes.ago]])

        result = BiggestVsSmallest.call([zero, one, two])

        by_id = result.index_by { |r| r[:entry].id }
        assert_not by_id[1][:complete]
        assert_not by_id[2][:complete]
        assert     by_id[3][:complete]
      end
    end
  end
end
