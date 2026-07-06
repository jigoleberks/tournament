module Leaderboards
  module Rankers
    # Win order: blackout (earliest) > most lines (earliest to that count) >
    # most squares (earliest to that count) > entry id. Built as a single
    # ascending sort_by so the leaderboard is a plain ordered list.
    class Bingo
      FAR_FUTURE = Time.utc(9999, 1, 1)

      def self.call(rows)
        rows
          .map { |row| decorate(row) }
          .sort_by { |row| sort_key(row) }
      end

      def self.decorate(row)
        r = row[:result]
        row.merge(squares_count: r.squares_count, lines_count: r.lines_count, blackout: r.blackout)
      end

      def self.sort_key(row)
        r = row[:result]
        [
          r.blackout ? 0 : 1,
          r.blackout_at || FAR_FUTURE,
          -r.lines_count,
          # "reach time" for this entry's own line count; compared only against
          # entries with the same lines_count because -lines_count precedes it.
          r.line_times[r.lines_count - 1] || FAR_FUTURE,
          -r.squares_count,
          r.square_times[r.squares_count - 1] || FAR_FUTURE,
          row[:entry].id
        ]
      end

      private_class_method :decorate, :sort_key
    end
  end
end
