module Tournaments
  # Distinct active teammates of `user` across every active team tournament in
  # `club`, de-duplicated and sorted by name. Backs the "who's this catch for?"
  # chooser. Returns [] when the user has no team tournaments or no teammates.
  #
  # "Teammate" stays defined by TeammatesFor; this just unions across tournaments.
  # We resolve teammates directly here rather than via TeammateLogTournamentsFor
  # so TeammatesFor runs once per tournament (tournaments with no teammate
  # contribute nothing) instead of twice — once to filter, once to collect.
  class TeammatesAcross
    def self.call(user:, club:)
      ActiveForUser.call(user: user)
        .select { |t| t.club_id == club.id && t.mode_team? }
        .flat_map { |t| TeammatesFor.call(user: user, tournament: t).to_a }
        .uniq(&:id)
        .sort_by(&:name)
    end
  end
end
