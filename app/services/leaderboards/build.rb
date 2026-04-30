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
        { entry: entry, total: total, fish: fish, fish_lengths: fish.map { |f| f[:length_inches] } }
      end
      rows.sort_by { |r| -r[:total] }
    end
  end
end
