module Leaderboards
  module Rankers
    class HiddenLength
      # Two modes:
      #   - target nil (pre-reveal):  one row per catch, sorted by length desc
      #     → captured_at_device asc → entry.id asc → catch.id asc.
      #   - target set (post-reveal): one row per entry, each represented by
      #     their catch with smallest |length - target|, sorted by that
      #     distance asc → that catch's captured_at_device asc → entry.id asc.
      #     Entries with no catches sort last.
      def self.call(entry_rows, tournament:)
        target = tournament.hidden_length_target
        target.nil? ? pre_reveal(entry_rows) : post_reveal(entry_rows, target)
      end

      def self.pre_reveal(entry_rows)
        far_future = ::Time.zone.at(0) + 100.years
        per_catch_rows = entry_rows.flat_map do |row|
          row[:fish].map do |f|
            {
              entry: row[:entry],
              total: f[:length_inches],
              fish: [f],
              fish_lengths: [f[:length_inches]],
              earliest_catch_at: f[:captured_at_device],
              complete: false
            }
          end
        end
        per_catch_rows.sort_by do |r|
          [
            -r[:total],
            r[:earliest_catch_at] || far_future,
            r[:entry].id,
            r[:fish].first[:id]
          ]
        end
      end

      def self.post_reveal(entry_rows, target)
        far_future = ::Time.zone.at(0) + 100.years
        target_d = target.to_d
        rows = entry_rows.map do |row|
          if row[:fish].empty?
            { entry: row[:entry], total: nil, fish: [], fish_lengths: [], earliest_catch_at: nil, complete: false, _distance: nil }
          else
            chosen = row[:fish].min_by { |f| (f[:length_inches].to_d - target_d).abs }
            distance = (chosen[:length_inches].to_d - target_d).abs
            {
              entry: row[:entry],
              total: chosen[:length_inches],
              fish: [chosen],
              fish_lengths: [chosen[:length_inches]],
              earliest_catch_at: chosen[:captured_at_device],
              complete: false,
              _distance: distance
            }
          end
        end
        rows.sort_by do |r|
          [
            r[:_distance].nil? ? 1 : 0,
            r[:_distance] || 0,
            r[:earliest_catch_at] || far_future,
            r[:entry].id
          ]
        end.each { |r| r.delete(:_distance) }
      end

      private_class_method :pre_reveal, :post_reveal
    end
  end
end
