module Leaderboards
  module Rankers
    class ProgressiveLength
      # Score = up-sizes = rungs - 1, clamped at 0 so an empty entry doesn't score
      # -1 and rank above the field. The :total key carries the up-size count (not
      # a length) so the leaderboard partial can use one accessor across formats —
      # same trick Rankers::Tagged uses for ticket counts.
      #
      # row[:fish] arrives in ladder order (slot_index asc), so fish.last is the
      # top rung and its captured_at_device is when the entry earned its final
      # up-size.
      #
      # Cascade: up-sizes desc → earliest final rung asc (the race) →
      # top rung desc → entry.id asc.
      def self.call(entry_rows)
        entry_rows.map do |row|
          row.merge(total: [row[:fish].size - 1, 0].max)
        end.sort_by do |r|
          top = r[:fish].last
          [
            -r[:total],
            (top && top[:captured_at_device]) || FAR_FUTURE,
            top ? -top[:length_inches] : 0,
            r[:entry].id
          ]
        end
      end
    end
  end
end
