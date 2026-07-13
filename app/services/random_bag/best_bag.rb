module RandomBag
  # Chooses the subset of at most MAX_FISH of a team's caught fish whose summed
  # length is closest to the team's target (over or under, absolute distance).
  # A pure function of (fish, target): the same result during play and at reveal.
  # Team catch counts are tiny, so a bounded combination search over sizes 1..5
  # is cheap. Ties keep the first subset found (smaller sizes are tried first,
  # so an exact single-fish match is preferred to a larger equal-distance bag).
  class BestBag
    MAX_FISH = 5

    # PERF: this is O(C(n,5)) per entry (n = the entry's caught fish), recomputed
    # on every leaderboard Build — i.e. on every catch broadcast and page view.
    # Fine at club scale (<~20 fish/team it's sub-ms), but Random Bag uniquely
    # rewards logging more fish (every extra catch can only improve the best bag),
    # so n trends higher than other formats. It gets noticeable ~25-30+ fish/team
    # and painful at 40+. If a high-volume/all-day event is planned, replace the
    # brute force with an O(n) DP over reachable sums — bucket at HUNDREDTHS, not
    # quarter-inches: cm-logged catches land off the 1/4" grid (see InferLoggedUnit),
    # so 1/4" buckets would approximate. Keep this method as the exact test oracle:
    # assert optimized(fish, target) == BestBag.call(...) over random inputs, and
    # preserve the tie rule below (smallest/earliest subset wins on equal distance).
    def self.call(fish:, target:)
      return { subset: [], sum: nil, distance: nil } if fish.empty? || target.nil?

      target_d = target.to_d
      best = nil
      max_k = [MAX_FISH, fish.size].min
      (1..max_k).each do |k|
        fish.combination(k).each do |subset|
          sum = subset.sum(BigDecimal(0)) { |f| f[:length_inches].to_d }
          distance = (sum - target_d).abs
          best = { subset: subset, sum: sum, distance: distance } if best.nil? || distance < best[:distance]
        end
      end
      best
    end
  end
end
