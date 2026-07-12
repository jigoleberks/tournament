module RandomBag
  # Chooses the subset of at most MAX_FISH of a team's caught fish whose summed
  # length is closest to the team's target (over or under, absolute distance).
  # A pure function of (fish, target): the same result during play and at reveal.
  # Team catch counts are tiny, so a bounded combination search over sizes 1..5
  # is cheap. Ties keep the first subset found (smaller sizes are tried first,
  # so an exact single-fish match is preferred to a larger equal-distance bag).
  class BestBag
    MAX_FISH = 5

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
