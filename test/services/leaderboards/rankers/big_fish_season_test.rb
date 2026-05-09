require "test_helper"

module Leaderboards
  module Rankers
    class BigFishSeasonTest < ActiveSupport::TestCase
      # Build minimal entry-row hashes shaped like Leaderboards::Build#build_rows output.
      # The ranker flattens these into one row per catch.
      Entry = Struct.new(:id, :display_name)

      def entry_row(entry_id:, catches: [])
        # `catches` is an array of [catch_id, length, captured_at_device]
        fish = catches.sort_by { |c| -c[1] }.map do |id, length, captured|
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

      test "returns one row per catch, sorted by length desc" do
        a = entry_row(entry_id: 1, catches: [[101, 25, 1.hour.ago], [102, 18, 30.minutes.ago]])
        b = entry_row(entry_id: 2, catches: [[201, 22, 45.minutes.ago]])

        result = BigFishSeason.call([a, b])

        assert_equal 3, result.size
        assert_equal [25, 22, 18], result.map { |r| r[:total] }
      end

      test "same angler can appear in multiple rows" do
        a = entry_row(entry_id: 1, catches: [[101, 25, 1.hour.ago], [102, 21, 45.minutes.ago], [103, 18, 30.minutes.ago]])
        b = entry_row(entry_id: 2, catches: [[201, 22, 50.minutes.ago]])

        result = BigFishSeason.call([a, b])

        assert_equal [1, 2, 1, 1], result.map { |r| r[:entry].id },
          "expected entry order: a (25), b (22), a (21), a (18)"
        assert_equal [25, 22, 21, 18], result.map { |r| r[:total] }
      end

      test "each row holds exactly one fish" do
        a = entry_row(entry_id: 1, catches: [[101, 25, 1.hour.ago], [102, 21, 45.minutes.ago]])

        result = BigFishSeason.call([a])

        result.each { |r| assert_equal 1, r[:fish].size }
      end

      test "entry with no catches contributes no rows" do
        empty = entry_row(entry_id: 1, catches: [])
        any   = entry_row(entry_id: 2, catches: [[201, 22, 1.hour.ago]])

        result = BigFishSeason.call([empty, any])

        assert_equal 1, result.size
        assert_equal 2, result.first[:entry].id
      end

      test "ties broken by earliest captured_at_device" do
        earlier = entry_row(entry_id: 1, catches: [[101, 22, 2.hours.ago]])
        later   = entry_row(entry_id: 2, catches: [[201, 22, 30.minutes.ago]])

        result = BigFishSeason.call([earlier, later])

        assert_equal [1, 2], result.map { |r| r[:entry].id }
      end

      test "ties with equal captured_at_device broken by entry.id ascending" do
        same_time = 1.hour.ago
        a = entry_row(entry_id: 7, catches: [[101, 22, same_time]])
        b = entry_row(entry_id: 3, catches: [[201, 22, same_time]])

        result = BigFishSeason.call([a, b])

        assert_equal [3, 7], result.map { |r| r[:entry].id }
      end

      test "row's earliest_catch_at and total reflect the single catch" do
        captured = 1.hour.ago
        row = entry_row(entry_id: 1, catches: [[101, 25, captured], [102, 18, 30.minutes.ago]])

        result = BigFishSeason.call([row])

        assert_in_delta captured, result.first[:earliest_catch_at], 1.second
        assert_equal 25, result.first[:total]
      end
    end
  end
end
