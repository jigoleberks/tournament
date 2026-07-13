module Leaderboards
  module Rankers
    # Beat the Average.
    #
    # During play (tournament not ended): one row per entry, each showing that
    # entry's own catches with the entry's OWN mean length as :total. The overall
    # winning average is NOT computed or exposed here — it's the hidden goal. The
    # own-entry-only ViewerScope means an angler sees only their own row anyway;
    # ordering among entries is cosmetic (earliest catch, then entry id).
    #
    # At reveal (tournament ended): compute avg = mean length of every placed
    # catch across all entries and species, then emit one row PER CATCH ranked by
    # |length - avg| asc -> captured_at asc -> entry.id -> catch.id. The first row
    # is the winner. Each revealed row carries :distance for the score column.
    class BeatTheAverage
      def self.call(entry_rows, tournament:)
        tournament.ended?(at: Time.current) ? revealed(entry_rows) : during_play(entry_rows)
      end

      def self.during_play(entry_rows)
        entry_rows.map do |row|
          {
            entry: row[:entry],
            total: mean(row[:fish_lengths]),   # entry's own average (nil if no fish)
            fish: row[:fish],
            fish_lengths: row[:fish_lengths],
            earliest_catch_at: row[:earliest_catch_at],
            complete: false
          }
        end.sort_by { |r| [r[:earliest_catch_at] || FAR_FUTURE, r[:entry].id] }
      end

      def self.revealed(entry_rows)
        avg = mean(entry_rows.flat_map { |r| r[:fish_lengths] })
        return [] if avg.nil?

        per_catch = entry_rows.flat_map do |row|
          row[:fish].map do |f|
            {
              entry: row[:entry],
              total: f[:length_inches],
              fish: [f],
              fish_lengths: [f[:length_inches]],
              earliest_catch_at: f[:captured_at_device],
              complete: false,
              distance: (f[:length_inches].to_d - avg).abs
            }
          end
        end

        per_catch.sort_by do |r|
          [r[:distance], r[:earliest_catch_at] || FAR_FUTURE, r[:entry].id, r[:fish].first[:id]]
        end
      end

      # Single source of the "average" formula: arithmetic mean of length_inches as
      # BigDecimal; nil if empty.
      def self.mean(lengths)
        return nil if lengths.empty?
        lengths.sum(BigDecimal(0)) { |l| l.to_d } / lengths.size
      end

      # Overall average from a tournament's active placements — used by the reveal
      # banner and the end-of-tournament push so the number they show matches the
      # ranking. nil if no placed catches.
      def self.average_for(tournament)
        lengths = CatchPlacement.active
          .where(tournament_id: tournament.id)
          .joins(:catch)
          .pluck("catches.length_inches")
        mean(lengths)
      end

      private_class_method :during_play, :revealed
    end
  end
end
