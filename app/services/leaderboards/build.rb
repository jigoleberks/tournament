module Leaderboards
  class Build
    def self.call(tournament:, entries: nil, placements: nil, total_capacity: nil, bingo_species_ids: nil)
      if tournament.format_bingo?
        return Leaderboards::Rankers::Bingo.call(
          bingo_rows(tournament, entries: entries, species_ids: bingo_species_ids)
        )
      end

      rows = build_rows(tournament, entries: entries, placements: placements, total_capacity: total_capacity)
      case tournament.format
      when "hidden_length"       then Leaderboards::Rankers::HiddenLength.call(rows, tournament: tournament)
      when "big_fish_season"     then Leaderboards::Rankers::BigFishSeason.call(rows)
      when "biggest_vs_smallest" then Leaderboards::Rankers::BiggestVsSmallest.call(rows)
      when "fish_train"          then Leaderboards::Rankers::FishTrain.call(rows)
      when "tagged"              then Leaderboards::Rankers::Tagged.call(rows)
      when "smallest_fish"       then Leaderboards::Rankers::SmallestFish.call(rows)
      when "pro_walleye"         then Leaderboards::Rankers::ProWalleye.call(rows)
      when "progressive_length"  then Leaderboards::Rankers::ProgressiveLength.call(rows)
      when "beat_the_average"    then Leaderboards::Rankers::BeatTheAverage.call(rows, tournament: tournament)
      when "random_bag"          then Leaderboards::Rankers::RandomBag.call(rows, tournament: tournament)
      else                            Leaderboards::Rankers::Standard.call(rows)
      end
    end

    def self.build_rows(tournament, entries: nil, placements: nil, total_capacity: nil)
      entries ||= tournament.tournament_entries.includes(:users)
      if tournament.format_random_bag?
        entries = entries.to_a
        entries.each { |e| ::RandomBag::AssignTarget.call(entry: e, tournament: tournament) }
      end
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
        fish = if tournament.format_fish_train? || tournament.format_progressive_length?
          # Fish Train: train order. Progressive Length: ladder order, rung 0 first.
          fish.sort_by { |f| f[:slot_index] }
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
          target: entry.random_bag_target_inches,
          complete: total_capacity > 0 && placements.size >= total_capacity
        }
      end
    end

    private_class_method :build_rows

    def self.bingo_rows(tournament, entries: nil, species_ids: nil)
      entries = (entries || tournament.tournament_entries).to_a
      # The bingo species ids are the same for every bingo tournament; a caller
      # building many boards at once (WinnersFor / SeasonPoints::Standings) resolves
      # them once and injects via species_ids: so we don't re-query Species per
      # tournament. Each entrant's in-window catches are still loaded per tournament
      # (its window bounds the query) but batched into two queries per tournament.
      species_ids ||= Catches::Bingo::EvaluateCard.species_id_map
      catches_by_entry = Catches::Bingo::EvaluateCard.catches_by_entry(
        tournament: tournament, entries: entries
      )
      entries.map do |entry|
        catches = catches_by_entry[entry.id]
        result = Catches::Bingo::EvaluateCard.call(
          tournament: tournament, entry: entry, species_ids: species_ids,
          catches: catches
        )
        # Carry the loaded CatchLites so a caller that needs a "card minus one
        # catch" (PlaceInSlots' took-the-lead detection) can re-evaluate without
        # re-running catches_by_entry.
        { entry: entry, result: result, catches: catches || [] }
      end
    end
    private_class_method :bingo_rows
  end
end
