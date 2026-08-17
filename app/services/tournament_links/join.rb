module TournamentLinks
  # Puts two team tournaments in one link group, then back-fills entries in both
  # directions so a pair linked after the roster was started doesn't sit half
  # synced. Adopts an existing group id when either side already has one.
  class Join
    def self.call(tournament:, other:, notify: true)
      new(tournament: tournament, other: other, notify: notify).call
    end

    # notify: is passed straight through to both back-fill passes; see
    # SyncEntry for why it exists and why it defaults to true.
    def initialize(tournament:, other:, notify: true)
      @tournament = tournament
      @other = other
      @notify = notify
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
        #
        # prune: false on both passes: this back-fill is a union of the two
        # rosters, not "whichever side called Join wins". Without it, syncing
        # @tournament's entries first would use its (possibly smaller) crew
        # as the source of truth and prune members off @other's matching
        # entry that were never meant to be removed — dropping their catch
        # placements along with them.
        @tournament.tournament_entries.each { |e| SyncEntry.call(entry: e, prune: false, notify: @notify) }
        @other.tournament_entries.each { |e| SyncEntry.call(entry: e, prune: false, notify: @notify) }
      end
    end
  end
end
