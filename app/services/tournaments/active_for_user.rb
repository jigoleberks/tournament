module Tournaments
  class ActiveForUser
    def self.call(user:, at: Time.current)
      with_entries(user: user, at: at).map { |row| row[:tournament] }
    end

    def self.with_entries(user:, at: Time.current)
      tournaments = Tournament
        .joins(tournament_entries: :tournament_entry_members)
        .where(tournament_entry_members: { user_id: user.id })
        # A judge is never scored in a tournament they judge. Exclude via a
        # subquery, NOT a left_joins(:tournament_judges) — that join fans out a
        # row per judge and double-scores the catch in append-only formats (the
        # bug the .uniq below now also guards). New judge/entrant overlap is
        # blocked by validations, but legacy rows predating them still exist.
        .where.not(id: TournamentJudge.where(user_id: user.id).select(:tournament_id))
        .where("starts_at <= ?", at)
        .where("ends_at IS NULL OR ends_at >= ?", at)
        .select("tournaments.*, tournament_entries.id AS entry_id")
        .to_a
        # A user holds at most one entry per tournament, so one row per entry is
        # the contract every caller relies on. PlaceInSlots iterates these rows,
        # and the append-only formats (Hidden Length, Tagged) create a placement
        # per iteration — a duplicate row silently double-scores the catch.
        # Adding any has_many join above (a left_joins(:tournament_judges) once
        # did) fans out a row per associated record, so dedupe before returning.
        .uniq(&:entry_id)

      entries_by_id = TournamentEntry.where(id: tournaments.map(&:entry_id)).index_by(&:id)
      tournaments.map { |t| { tournament: t, entry: entries_by_id[t.entry_id] } }
    end
  end
end
