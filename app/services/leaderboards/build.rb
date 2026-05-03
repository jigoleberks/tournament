module Leaderboards
  class Build
    def self.call(tournament:)
      entries = tournament.tournament_entries.includes(:users)
      placements_by_entry = CatchPlacement.active
        .where(tournament_id: tournament.id)
        .includes(catch: :species)
        .group_by(&:tournament_entry_id)

      rows = entries.map do |entry|
        placements = placements_by_entry[entry.id] || []
        fish = placements.map { |p| { id: p.catch.id, length_inches: p.catch.length_inches, species_name: p.catch.species.name } }
        total = fish.sum { |f| f[:length_inches] }
        earliest = placements.map { |p| p.catch.captured_at_device }.compact.min
        {
          entry: entry,
          total: total,
          fish: fish,
          fish_lengths: fish.map { |f| f[:length_inches] },
          earliest_catch_at: earliest
        }
      end
      rank(rows)
    end

    # Cascade tiebreaker: total desc → largest single fish desc → 2nd largest desc → ...
    # → earliest captured_at_device asc → entry.id asc.
    def self.rank(rows)
      max_fish = rows.map { |r| r[:fish].size }.max || 0
      far_future = ::Time.zone.at(0) + 100.years
      rows.sort_by do |r|
        fish_desc = r[:fish].map { |f| f[:length_inches] }.sort.reverse
        fish_padded = fish_desc + [0] * (max_fish - fish_desc.size)
        [
          -r[:total],
          *fish_padded.map { |l| -l },
          r[:earliest_catch_at] || far_future,
          r[:entry].id
        ]
      end
    end
  end
end
