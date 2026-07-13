require "test_helper"

module Leaderboards
  class QualifiedRowsTest < ActiveSupport::TestCase
    Entry = Struct.new(:id)

    def length_row(entry_id, fish_count)
      { entry: Entry.new(entry_id), fish: Array.new(fish_count) { { length_inches: 12 } } }
    end

    def bingo_row(entry_id, squares_count)
      { entry: Entry.new(entry_id), squares_count: squares_count }
    end

    test "length formats keep entries with at least one scoring fish" do
      t = Tournament.new(format: :standard)
      rows = [length_row(1, 2), length_row(2, 1), length_row(3, 0)]
      kept = QualifiedRows.call(tournament: t, rows: rows)
      assert_equal [1, 2], kept.map { |r| r[:entry].id }
    end

    test "progressive length rejects entries that never up-sized (single fish, zero up-sizes)" do
      t = Tournament.new(format: :progressive_length)
      # entry 1 up-sized once (2 fish); entry 2 caught a single fish (0 up-sizes);
      # entry 3 caught nothing. Only entry 1 actually progressed the ladder.
      rows = [length_row(1, 2), length_row(2, 1), length_row(3, 0)]
      kept = QualifiedRows.call(tournament: t, rows: rows)
      assert_equal [1], kept.map { |r| r[:entry].id },
        "a lone fish is 0 up-sizes and must not qualify for a win or season points"
    end

    test "bingo rejects entries holding only the free centre square" do
      t = Tournament.new(format: :bingo)
      rows = [bingo_row(1, 3), bingo_row(2, 1), bingo_row(3, 0)]
      kept = QualifiedRows.call(tournament: t, rows: rows)
      assert_equal [1], kept.map { |r| r[:entry].id }
    end

    test "beat the average dedupes per-catch rows to one row per entry, keeping the closest" do
      t = Tournament.new(format: :beat_the_average)
      # Revealed board is one row PER CATCH, sorted closest-to-average first.
      # Entry 1 owns the two closest catches (rows 0 and 1); entry 2 owns the third.
      rows = [length_row(1, 1), length_row(1, 1), length_row(2, 1)]
      kept = QualifiedRows.call(tournament: t, rows: rows)
      assert_equal [1, 2], kept.map { |r| r[:entry].id },
        "each entry should place at most once, by its closest catch, not once per catch"
    end
  end
end
