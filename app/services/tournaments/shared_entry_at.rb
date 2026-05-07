module Tournaments
  # Returns the TournamentEntry shared by both users, in a tournament that is
  # active at `at`, in `club`. Returns nil if the users do not sit in the same
  # boat together at that time.
  #
  # "Teammate" semantics in this app are per-tournament-entry: two anglers are
  # only teammates if they are members of the same TournamentEntry, scoped to a
  # tournament whose start/end window includes the catch time.
  class SharedEntryAt
    def self.call(user_a:, user_b:, club:, at: Time.current)
      return nil if user_a.id == user_b.id

      TournamentEntry
        .joins(:tournament)
        .where(tournaments: { club_id: club.id })
        .where("tournaments.starts_at <= ?", at)
        .where("tournaments.ends_at IS NULL OR tournaments.ends_at >= ?", at)
        .where(id: TournamentEntryMember.where(user_id: user_a.id).select(:tournament_entry_id))
        .where(id: TournamentEntryMember.where(user_id: user_b.id).select(:tournament_entry_id))
        .first
    end
  end
end
