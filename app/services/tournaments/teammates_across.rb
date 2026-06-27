module Tournaments
  # Distinct active teammates of `user` across every active team tournament in
  # `club` (the tournaments TeammateLogTournamentsFor returns), de-duplicated and
  # sorted by name. Backs the "who's this catch for?" chooser. Returns [] when the
  # user has no team tournaments or no teammates.
  #
  # "Teammate" stays defined by TeammatesFor; this just unions across tournaments.
  class TeammatesAcross
    def self.call(user:, club:)
      TeammateLogTournamentsFor.call(user: user, club: club)
        .flat_map { |t| TeammatesFor.call(user: user, tournament: t).to_a }
        .uniq(&:id)
        .sort_by(&:name)
    end
  end
end
