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

      destroyed = 0
      siblings.each do |sibling|
        counterpart = Counterpart.find(entry: @entry, sibling: sibling)
        next if counterpart.nil?
        counterpart_id = counterpart.id
        counterpart.destroy!
        destroyed += 1
        ::Placements::BroadcastLeaderboard.call(
          tournament: sibling, changed_entry_ids: [counterpart_id]
        )
      end
      destroyed
    end
  end
end
