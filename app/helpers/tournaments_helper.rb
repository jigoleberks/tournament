module TournamentsHelper
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
