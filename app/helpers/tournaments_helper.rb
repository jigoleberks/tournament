module TournamentsHelper
  # Once a team tournament has ended, list the members beneath a team's name —
  # but only when a custom team name is set. Without a custom name, display_name
  # already shows the joined member names, so a roster would be redundant.
  def team_roster_line(tournament, entry)
    return unless tournament.mode_team? && tournament.ended? && entry.name.present?
    entry.users.map(&:name).join(" + ")
  end
end
