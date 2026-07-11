require "test_helper"

module Leaderboards
  module Rankers
    class BeatTheAverageTest < ActiveSupport::TestCase
      Entry = Struct.new(:id, :display_name)
      FakeTournament = Struct.new(:ended) do
        def format_beat_the_average? = true
        def ended?(at: Time.current) = ended
      end

      def entry_row(entry_id:, catches: [])
        # catches: array of [catch_id, length, captured_at_device]
        fish = catches.map do |id, length, captured|
          { id: id, length_inches: length, captured_at_device: captured,
            species_name: "Walleye", angler_name: "Angler #{entry_id}",
            logged_by_name: nil, approver_name: nil, length_unit: "inches" }
        end
        { entry: Entry.new(entry_id, "Entry #{entry_id}"),
          total: fish.sum { |f| f[:length_inches] },
          fish: fish, fish_lengths: fish.map { |f| f[:length_inches] },
          earliest_catch_at: fish.map { |f| f[:captured_at_device] }.compact.min,
          complete: false }
      end

      test "during play: one row per entry, total is that entry's own mean" do
        t = FakeTournament.new(false)
        a = entry_row(entry_id: 1, catches: [[101, 10, 2.hours.ago], [102, 20, 1.hour.ago]])
        b = entry_row(entry_id: 2, catches: [[201, 15, 90.minutes.ago]])

        result = BeatTheAverage.call([a, b], tournament: t)

        by_entry = result.index_by { |r| r[:entry].id }
        assert_equal BigDecimal("15"), by_entry[1][:total]   # (10+20)/2
        assert_equal BigDecimal("15"), by_entry[2][:total]   # 15/1
        assert_nil by_entry[1][:distance], "no overall distance leaked during play"
      end

      test "during play: entry with no fish has nil total" do
        t = FakeTournament.new(false)
        empty = entry_row(entry_id: 3, catches: [])
        result = BeatTheAverage.call([empty], tournament: t)
        assert_nil result.first[:total]
      end

      test "revealed: one row per catch ranked by distance to combined average" do
        t = FakeTournament.new(true)
        # walleye + pike combined: 12,14,15,28,31,33 -> avg 22.166...
        a = entry_row(entry_id: 1, catches: [[101, 12, 5.hours.ago], [102, 14, 4.hours.ago], [103, 15, 3.hours.ago]])
        b = entry_row(entry_id: 2, catches: [[201, 28, 2.hours.ago], [202, 31, 90.minutes.ago], [203, 33, 1.hour.ago]])

        result = BeatTheAverage.call([a, b], tournament: t)

        assert_equal 6, result.size, "flat: one row per catch"
        assert_equal 201, result.first[:fish].first[:id], "28\" is closest to 22.17"
        # distances strictly non-decreasing
        dists = result.map { |r| r[:distance] }
        assert_equal dists, dists.sort
      end

      test "revealed: ties broken by earliest captured_at, then entry id, then catch id" do
        t = FakeTournament.new(true)
        # avg of 10 and 20 is 15; both catches are 5 off. earlier one wins.
        a = entry_row(entry_id: 1, catches: [[101, 20, 1.hour.ago]])
        b = entry_row(entry_id: 2, catches: [[201, 10, 2.hours.ago]])
        result = BeatTheAverage.call([a, b], tournament: t)
        assert_equal 201, result.first[:fish].first[:id], "earlier catch wins the tie"
      end

      test "revealed: no fish -> empty board" do
        t = FakeTournament.new(true)
        assert_equal [], BeatTheAverage.call([entry_row(entry_id: 1, catches: [])], tournament: t)
      end

      test "revealed: single fish is the average and wins with distance 0" do
        t = FakeTournament.new(true)
        a = entry_row(entry_id: 1, catches: [[101, 17, 1.hour.ago]])
        result = BeatTheAverage.call([a], tournament: t)
        assert_equal 1, result.size
        assert_equal BigDecimal("0"), result.first[:distance]
      end

      test "mean is nil for empty and arithmetic otherwise" do
        assert_nil BeatTheAverage.mean([])
        assert_equal BigDecimal("15"), BeatTheAverage.mean([10, 20])
      end
    end
  end
end
