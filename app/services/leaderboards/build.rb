module Leaderboards
  class Build
    def self.call(tournament:)
      rows = build_rows(tournament)
      case tournament.format
      when "hidden_length"       then Leaderboards::Rankers::HiddenLength.call(rows, tournament: tournament)
      when "big_fish_season"     then Leaderboards::Rankers::BigFishSeason.call(rows)
      when "biggest_vs_smallest" then Leaderboards::Rankers::BiggestVsSmallest.call(rows)
      else                            Leaderboards::Rankers::Standard.call(rows)
      end
    end

    def self.build_rows(tournament)
      entries = tournament.tournament_entries.includes(:users)
      placements_by_entry = CatchPlacement.active
        .where(tournament_id: tournament.id)
        .includes(catch: [:species, :user, :logged_by_user, { judge_actions: :judge_user }])
        .group_by(&:tournament_entry_id)

      total_capacity = tournament.scoring_slots.sum(:slot_count)

      entries.map do |entry|
        placements = placements_by_entry[entry.id] || []
        fish = placements
          .map { |p|
            {
              id: p.catch.id,
              length_inches: p.catch.length_inches,
              captured_at_device: p.catch.captured_at_device,
              species_name: p.catch.species.name,
              angler_name: p.catch.user.name,
              logged_by_name: p.catch.logged_by_user&.name,
              approver_name: p.catch.latest_approver&.name
            }
          }
          .sort_by { |f| -f[:length_inches] }
        total = fish.sum { |f| f[:length_inches] }
        earliest = placements.map { |p| p.catch.captured_at_device }.compact.min
        {
          entry: entry,
          total: total,
          fish: fish,
          fish_lengths: fish.map { |f| f[:length_inches] },
          earliest_catch_at: earliest,
          complete: total_capacity > 0 && placements.size >= total_capacity
        }
      end
    end

    private_class_method :build_rows
  end
end
