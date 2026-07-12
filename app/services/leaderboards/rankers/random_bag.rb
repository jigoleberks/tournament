module Leaderboards
  module Rankers
    # Random Bag.
    #
    # Each entry has its OWN random target (row[:target]). An entry's score is the
    # subset of <=5 of its caught fish summing closest to that target
    # (RandomBag::BestBag), and distance = |bag_sum - target|. One row per entry,
    # both during play and at reveal — identical computation. During play the
    # own-entry-only ViewerScope shows a team just its own row (with its known
    # target); at reveal the full board is shown, ranked by distance.
    #
    # Ranking: distance asc -> earliest qualifying-catch time -> entry.id. Entries
    # with no target yet (pre-first-view) or no fish have nil distance and sink to
    # the bottom (their score column renders "—").
    class RandomBag
      FAR_FUTURE = Time.utc(9999, 1, 1)

      def self.call(entry_rows, tournament: nil)
        rows = entry_rows.map do |row|
          bag = ::RandomBag::BestBag.call(fish: row[:fish], target: row[:target])
          {
            entry: row[:entry],
            target: row[:target],
            total: bag[:sum],
            fish: bag[:subset],
            fish_lengths: bag[:subset].map { |f| f[:length_inches] },
            earliest_catch_at: row[:earliest_catch_at],
            distance: bag[:distance],
            complete: false
          }
        end

        rows.sort_by do |r|
          [r[:distance].nil? ? 1 : 0, r[:distance] || BigDecimal(0),
           r[:earliest_catch_at] || FAR_FUTURE, r[:entry].id]
        end
      end
    end
  end
end
