module Leaderboards
  class Build
    def self.call(tournament:, entries: nil, placements: nil, total_capacity: nil)
      rows = build_rows(tournament, entries: entries, placements: placements, total_capacity: total_capacity)
      case tournament.format
      when "hidden_length"       then Leaderboards::Rankers::HiddenLength.call(rows, tournament: tournament)
      when "big_fish_season"     then Leaderboards::Rankers::BigFishSeason.call(rows)
      when "biggest_vs_smallest" then Leaderboards::Rankers::BiggestVsSmallest.call(rows)
      when "fish_train"          then Leaderboards::Rankers::FishTrain.call(rows)
      when "tagged"              then Leaderboards::Rankers::Tagged.call(rows)
      when "smallest_fish"       then Leaderboards::Rankers::SmallestFish.call(rows)
      when "pro_walleye"         then Leaderboards::Rankers::ProWalleye.call(rows)
      else                            Leaderboards::Rankers::Standard.call(rows)
      end
    end

    def self.build_rows(tournament, entries: nil, placements: nil, total_capacity: nil)
      entries ||= tournament.tournament_entries.includes(:users)
      placements ||= CatchPlacement.active
        .where(tournament_id: tournament.id)
        .includes(catch: [:species, :user, :logged_by_user, { judge_actions: :judge_user }])
      placements_by_entry = placements.group_by(&:tournament_entry_id)

      total_capacity ||= tournament.scoring_slots.sum(:slot_count)

      entries.map do |entry|
        placements = placements_by_entry[entry.id] || []
        fish = placements
          .map { |p|
            {
              id: p.catch.id,
              length_inches: p.catch.length_inches,
              length_unit: p.catch.length_unit,
              captured_at_device: p.catch.captured_at_device,
              species_name: p.catch.species.name,
              tag_number: p.catch.tag_number,
              angler_name: p.catch.user.name,
              logged_by_name: p.catch.logged_by_user&.name,
              approver_name: p.catch.latest_approver&.name,
              slot_index: p.slot_index
            }
          }
        fish = if tournament.format_fish_train?
          fish.sort_by { |f| f[:slot_index] }                # train order
        elsif tournament.format_tagged?
          # Tickets in the order they were earned — matches the angler's mental
          # model and the way tags are read off the row in the partial.
          fish.sort_by { |f| f[:captured_at_device] || Time.at(0) }
        elsif tournament.format_smallest_fish?
          fish.sort_by { |f| f[:length_inches] }             # smallest-first
        else
          fish.sort_by { |f| -f[:length_inches] }            # biggest-first (default)
        end
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
