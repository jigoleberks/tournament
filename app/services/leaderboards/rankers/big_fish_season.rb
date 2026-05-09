module Leaderboards
  module Rankers
    class BigFishSeason
      # Big Fish Season shows one row per catch (not per entry). Multiple catches
      # by the same angler each get their own row. Sort by length desc, then by
      # earliest captured_at_device, then entry.id, then catch.id for stability.
      def self.call(entry_rows, tournament: nil)
        _ = tournament  # accepted for ranker uniformity; BigFishSeason does not use it
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
    end
  end
end
