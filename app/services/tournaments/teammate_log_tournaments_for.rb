module Tournaments
  # Active, team-mode tournaments where `user` has at least one active teammate.
  # Drives the home-page "Log for teammate" button (visibility + link target)
  # and the aggregated teammate picker. Returns [] when there are none.
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
