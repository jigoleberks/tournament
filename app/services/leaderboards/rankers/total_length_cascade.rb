module Leaderboards
  module Rankers
    # Shared total-length ranking cascade for Standard and Pro Walleye. Both sort
    # by: total desc -> largest single fish desc -> 2nd largest desc -> ... ->
    # earliest captured_at_device asc -> entry.id asc. They differ only in whether
    # a complete basket is tiered ahead of an incomplete one before total is even
    # compared:
    #   Standard    (tier_complete: true)  — a full basket always outranks a
    #                                        partial one, even a heavier partial.
    #   Pro Walleye (tier_complete: false) — pure weight; a heavier 4-fish partial
    #                                        can beat a lighter full 5-fish basket.
    module TotalLengthCascade
      def self.call(rows, tier_complete:)
        max_fish = rows.map { |r| r[:fish].size }.max || 0
        rows.sort_by do |r|
          fish_desc = r[:fish].map { |f| f[:length_inches] }.sort.reverse
          fish_padded = fish_desc + [0] * (max_fish - fish_desc.size)
          [
            *(tier_complete ? [r[:complete] ? 0 : 1] : []),
            -r[:total],
            *fish_padded.map { |l| -l },
            r[:earliest_catch_at] || FAR_FUTURE,
            r[:entry].id
          ]
        end
      end
    end
  end
end
