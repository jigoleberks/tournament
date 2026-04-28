module Leaderboards
  class Build
    def self.call(tournament:)
      rows = tournament.tournament_entries.includes(:users).map do |entry|
        placements = CatchPlacement.active
          .where(tournament_entry_id: entry.id)
          .includes(:catch)
        total = placements.sum { |p| p.catch.length_inches }
        fish = placements.map { |p| { id: p.catch.id, length_inches: p.catch.length_inches } }
        { entry: entry, total: total, fish: fish, fish_lengths: fish.map { |f| f[:length_inches] } }
      end
      rows.sort_by { |r| -r[:total] }
    end
  end
end
