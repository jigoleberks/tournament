require "test_helper"

module Leaderboards
  module Rankers
    class BingoTest < ActiveSupport::TestCase
      Entry = Struct.new(:id, :display_name)
      R = Catches::Bingo::EvaluateCard::Result

      def row(id:, lines: 0, squares: 1, line_times: [], square_times: [], blackout: false, blackout_at: nil)
        { entry: Entry.new(id, "E#{id}"),
          result: R.new(cells: [], squares_count: squares, square_times: square_times,
                        lines_count: lines, line_times: line_times,
                        blackout: blackout, blackout_at: blackout_at) }
      end

      test "blackout beats more lines" do
        t = Time.utc(2026, 7, 6, 1, 0)
        black = row(id: 1, blackout: true, blackout_at: t, lines: 12, squares: 25)
        liner = row(id: 2, lines: 4, squares: 20)
        assert_equal [1, 2], Bingo.call([liner, black]).map { |r| r[:entry].id }
      end

      test "more lines beats fewer lines" do
        a = row(id: 1, lines: 2, line_times: [10.minutes.ago, 5.minutes.ago])
        b = row(id: 2, lines: 3, line_times: [12.minutes.ago, 8.minutes.ago, 4.minutes.ago])
        assert_equal [2, 1], Bingo.call([a, b]).map { |r| r[:entry].id }
      end

      test "equal lines broken by earliest to reach that count" do
        early = row(id: 1, lines: 2, line_times: [20.minutes.ago, 15.minutes.ago])
        late  = row(id: 2, lines: 2, line_times: [20.minutes.ago, 3.minutes.ago])
        assert_equal [1, 2], Bingo.call([late, early]).map { |r| r[:entry].id }
      end

      test "no lines: rank by squares then earliest to that count" do
        a = row(id: 1, lines: 0, squares: 4, square_times: [30.minutes.ago, 20.minutes.ago, 10.minutes.ago, 9.minutes.ago])
        b = row(id: 2, lines: 0, squares: 4, square_times: [30.minutes.ago, 20.minutes.ago, 10.minutes.ago, 2.minutes.ago])
        c = row(id: 3, lines: 0, squares: 3, square_times: [30.minutes.ago, 20.minutes.ago, 10.minutes.ago])
        assert_equal [1, 2, 3], Bingo.call([b, c, a]).map { |r| r[:entry].id }
      end
    end
  end
end
