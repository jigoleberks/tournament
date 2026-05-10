module Leaderboards
  module Rankers
    class FishTrain
      # Score = sum of car lengths. Ranks by total desc → cars-completed desc →
      # largest-fish cascade desc → earliest captured_at_device asc → entry.id asc.
      # row[:fish] is expected to be ordered by slot_index ascending so the
      # leaderboard partial can render cars in train order.
      def self.call(entry_rows)
        far_future = ::Time.zone.at(0) + 100.years
        rows = entry_rows.map do |row|
          fish = row[:fish]
          {
            entry: row[:entry],
            total: fish.sum { |f| f[:length_inches] },
            cars_completed: fish.size,
            fish: fish,
            fish_lengths_desc: fish.map { |f| f[:length_inches] }.sort.reverse,
            earliest_catch_at: fish.map { |f| f[:captured_at_device] }.compact.min
          }
        end
        max_cars = rows.map { |r| r[:fish_lengths_desc].size }.max || 0
        rows.sort_by do |r|
          [
            -r[:total],
            -r[:cars_completed],
            *Array.new(max_cars) { |i| -(r[:fish_lengths_desc][i] || 0) },
            r[:earliest_catch_at] || far_future,
            r[:entry].id
          ]
        end
      end
    end
  end
end
