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

        # Back-fill inside the same transaction as the group-id assignment: a
        # RecordInvalid partway through (e.g. a crew member who judges the
        # sibling tournament) must roll back the link itself, not just the
        # sync — otherwise the pair is left linked with a half-mirrored
        # roster, exactly the "never sit half-synced" state Join exists to
        # prevent.
        @tournament.tournament_entries.each { |e| SyncEntry.call(entry: e) }
        @other.tournament_entries.each { |e| SyncEntry.call(entry: e) }
      end
    end
  end
end
