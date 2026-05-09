require "test_helper"

module Leaderboards
  module Rankers
    class BigFishSeasonTest < ActiveSupport::TestCase
      # Build minimal row hashes shaped like Leaderboards::Build#build_rows output.
      # Stubs an `entry` with a stable `.id` so tiebreaks are deterministic.
      Entry = Struct.new(:id)

      def row(id:, lengths: [], earliest: nil)
        fish = lengths.sort.reverse.map { |l| { id: l, length_inches: l, species_name: "x",
                                                angler_name: "x", logged_by_name: nil, approver_name: nil } }
        {
          entry: Entry.new(id),
          total: fish.sum { |f| f[:length_inches] },
          fish: fish,
          fish_lengths: fish.map { |f| f[:length_inches] },
          earliest_catch_at: earliest,
          complete: false
        }
      end

      test "ranks entries by single biggest fish" do
        a = row(id: 1, lengths: [25])
        b = row(id: 2, lengths: [30])
        c = row(id: 3, lengths: [20])

        result = BigFishSeason.call([a, b, c], tournament: nil)
        assert_equal [2, 1, 3], result.map { |r| r[:entry].id }
      end

      test "tiebreaks by 2nd biggest when 1st biggest ties" do
        a = row(id: 1, lengths: [30, 18])
        b = row(id: 2, lengths: [30, 25])

        result = BigFishSeason.call([a, b], tournament: nil)
        assert_equal [2, 1], result.map { |r| r[:entry].id }
      end

      test "tiebreaks cascade through 3rd, 4th... biggest" do
        a = row(id: 1, lengths: [30, 25, 15])
        b = row(id: 2, lengths: [30, 25, 20])

        result = BigFishSeason.call([a, b], tournament: nil)
        assert_equal [2, 1], result.map { |r| r[:entry].id }
      end

      test "entry with one big fish outranks entry with multiple smaller fish" do
        loner   = row(id: 1, lengths: [30])
        grinder = row(id: 2, lengths: [25, 25, 25])

        result = BigFishSeason.call([loner, grinder], tournament: nil)
        assert_equal [1, 2], result.map { |r| r[:entry].id }
      end

      test "entry with no fish sorts last" do
        empty = row(id: 1, lengths: [])
        any   = row(id: 2, lengths: [12])

        result = BigFishSeason.call([empty, any], tournament: nil)
        assert_equal [2, 1], result.map { |r| r[:entry].id }
      end

      test "all-empty entries fall back to entry.id ordering" do
        a = row(id: 5, lengths: [])
        b = row(id: 2, lengths: [])
        c = row(id: 9, lengths: [])

        result = BigFishSeason.call([a, b, c], tournament: nil)
        assert_equal [2, 5, 9], result.map { |r| r[:entry].id }
      end

      test "tiebreaks identical fish lists by earliest_catch_at" do
        earlier = row(id: 1, lengths: [22], earliest: 1.hour.ago)
        later   = row(id: 2, lengths: [22], earliest: 10.minutes.ago)

        result = BigFishSeason.call([earlier, later], tournament: nil)
        assert_equal [1, 2], result.map { |r| r[:entry].id }
      end

      test "final tiebreak is entry.id ascending" do
        a = row(id: 7, lengths: [22])
        b = row(id: 3, lengths: [22])

        result = BigFishSeason.call([a, b], tournament: nil)
        assert_equal [3, 7], result.map { |r| r[:entry].id }
      end
    end
  end
end
