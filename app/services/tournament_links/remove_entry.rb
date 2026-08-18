module TournamentLinks
  # Destroys an entry's counterparts across its link group. Removal is silent by
  # design: once a boat is entered for the night it stays in, so a removal is
  # always undoing a mis-tap rather than pulling a scoring boat out mid-event.
  class RemoveEntry
    def self.call(entry:)
      new(entry: entry).call
    end

    def initialize(entry:)
      @entry = entry
    end

    def call
      siblings = @entry.tournament.linked_tournaments
      return 0 if siblings.empty?

      removed = []
      siblings.each do |sibling|
        counterpart = Counterpart.find(entry: @entry, sibling: sibling)
        next if counterpart.nil?
        counterpart_id = counterpart.id
        counterpart.destroy!
        removed << [sibling, counterpart_id]
      end

      # after_all_transactions_commit, for the reason spelled out at length in
      # SyncEntry: BroadcastLeaderboard pushes its frame synchronously, and the
      # entry controllers now wrap this call together with their own
      # entry.destroy! so the pair can't come apart. Broadcasting inline would
      # drop the Side row from connected viewers' screens while that outer
      # transaction is still open — and a rollback would leave the row gone on
      # screen but present in the DB, with no later event to put it back. Runs
      # immediately when there is no outer transaction.
      ::ActiveRecord.after_all_transactions_commit do
        removed.each do |sibling, counterpart_id|
          ::Placements::BroadcastLeaderboard.call(
            tournament: sibling, changed_entry_ids: [counterpart_id]
          )
        end
      end

      removed.size
    end
  end
end
