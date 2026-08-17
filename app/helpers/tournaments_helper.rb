module TournamentsHelper
  # The display name for each format enum key. Several of them don't titleize
  # into what the rest of the app calls them ("Catch the Average", not "Beat The
  # Average"; "Tagged Walleye", not "Tagged"), so every screen that lists formats
  # reads them from here rather than deriving them.
  FORMAT_LABELS = {
    "standard" => "Standard",
    "big_fish_season" => "Big Fish Season",
    "hidden_length" => "Hidden Length",
    "biggest_vs_smallest" => "Biggest vs Smallest",
    "fish_train" => "Fish Train",
    "tagged" => "Tagged Walleye",
    "smallest_fish" => "Smallest Fish",
    "pro_walleye" => "Pro Walleye",
    "bingo" => "Bingo",
    "progressive_length" => "Progressive Length",
    "beat_the_average" => "Catch the Average",
    "random_bag" => "Random Bag"
  }.freeze

  def format_label(key)
    FORMAT_LABELS.fetch(key.to_s) { key.to_s.titleize }
  end

  # Once a team tournament has ended, list the members beneath a team's name —
  # but only when a custom team name is set. Without a custom name, display_name
  # already shows the joined member names, so a roster would be redundant.
  def team_roster_line(tournament, entry)
    return unless tournament.mode_team? && tournament.ended? && entry.name.present?
    # Ordered by join-row id (the order members were added to the entry) —
    # unordered, Postgres returns rows in arbitrary order and the roster
    # flips between renders.
    entry.users.order("tournament_entry_members.id").map(&:name).join(" + ")
  end
end
