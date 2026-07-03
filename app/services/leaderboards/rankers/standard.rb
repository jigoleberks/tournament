module Leaderboards
  module Rankers
    class Standard
      # Complete baskets tier ahead of incomplete ones, then the shared total-length
      # cascade (total desc → largest fish desc → … → earliest → entry.id).
      def self.call(rows)
        TotalLengthCascade.call(rows, tier_complete: true)
      end
    end
  end
end
