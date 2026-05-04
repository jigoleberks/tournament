module Tournaments
  class ActiveForUser
    def self.call(user:, at: Time.current)
      with_entries(user: user, at: at).map { |row| row[:tournament] }
    end

    def self.with_entries(user:, at: Time.current)
      tournaments = Tournament
        .joins(tournament_entries: :tournament_entry_members)
        .left_joins(:tournament_judges)
        .where(tournament_entry_members: { user_id: user.id })
        .where("tournament_entry_members.created_at <= ?", at)
        .where("tournament_judges.user_id IS DISTINCT FROM ?", user.id)
        .where("starts_at <= ?", at)
        .where("ends_at IS NULL OR ends_at >= ?", at)
        .select("tournaments.*, tournament_entries.id AS entry_id")
        .to_a

      entries_by_id = TournamentEntry.where(id: tournaments.map(&:entry_id)).index_by(&:id)
      tournaments.map { |t| { tournament: t, entry: entries_by_id[t.entry_id] } }
    end
  end
end
