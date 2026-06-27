module Tournaments
  # Active, team-mode tournaments where `user` has at least one active teammate.
  # Drives whether the "Log Catch" button routes to the teammate chooser (home
  # page) and backs TeammatesAcross's aggregated list. Returns [] when none.
  #
  # Re-checks TeammatesFor per tournament; at club scale the user is in only a
  # handful of active tournaments, so the extra query is negligible.
  class TeammateLogTournamentsFor
    def self.call(user:, club:)
      ActiveForUser.call(user: user)
        .select { |t| t.club_id == club.id }
        .select(&:mode_team?)
        .select { |t| TeammatesFor.call(user: user, tournament: t).exists? }
    end
  end
end
