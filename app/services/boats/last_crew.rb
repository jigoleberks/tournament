module Boats
  # Who was aboard this boat the last time it fished, before the given
  # tournament. Derived rather than stored: crews churn week to week (Majestic
  # Red ran six different crews in six nights), so a stored default would be
  # wrong more often than right — but for the boats that never change, this is
  # a one-tap refill.
  class LastCrew
    def self.call(boat:, before_tournament:)
      new(boat: boat, before_tournament: before_tournament).call
    end

    def initialize(boat:, before_tournament:)
      @boat = boat
      @before_tournament = before_tournament
    end

    def call
      entry = ::TournamentEntry
        .joins(:tournament)
        .where(boat_id: @boat.id)
        .where.not(tournament_id: @before_tournament.id)
        .where("tournaments.starts_at < ?", @before_tournament.starts_at)
        .order("tournaments.starts_at DESC")
        .first
      return [] if entry.nil?
      entry.users.to_a
    end
  end
end
