module Tournaments
  # Active teammates of `user` in `tournament`: other members of the
  # tournament_entries that `user` is in. Excludes deactivated users and
  # the user themselves. Returns [] if user has no entry in this tournament.
  class TeammatesFor
    def self.call(user:, tournament:)
      entry_ids = tournament.tournament_entries
        .joins(:tournament_entry_members)
        .where(tournament_entry_members: { user_id: user.id })
        .pluck(:id)
      return User.none if entry_ids.empty?

      User.active
        .joins(:tournament_entry_members)
        .where(tournament_entry_members: { tournament_entry_id: entry_ids })
        .where.not(id: user.id)
        .distinct
        .order(:name)
    end
  end
end
