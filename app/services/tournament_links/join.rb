module TournamentLinks
  # Puts two team tournaments in one link group, then back-fills entries in both
  # directions so a pair linked after the roster was started doesn't sit half
  # synced. Adopts an existing group id when either side already has one.
  class Join
    def self.call(tournament:, other:)
      new(tournament: tournament, other: other).call
    end

    def initialize(tournament:, other:)
      @tournament = tournament
      @other = other
    end

    def call
      group = @tournament.link_group_id.presence || @other.link_group_id.presence || SecureRandom.uuid
      Tournament.transaction do
        @tournament.update!(link_group_id: group)
        @other.update!(link_group_id: group)
      end

      @tournament.tournament_entries.each { |e| SyncEntry.call(entry: e) }
      @other.tournament_entries.each { |e| SyncEntry.call(entry: e) }
    end
  end
end
