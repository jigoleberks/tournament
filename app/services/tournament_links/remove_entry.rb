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
        counterpart = find_counterpart(sibling)
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

    private

    def find_counterpart(sibling)
      if @entry.boat_id
        by_boat = sibling.tournament_entries.find_by(boat_id: @entry.boat_id)
        return by_boat if by_boat
      end
      name = @entry.name.to_s.strip
      return nil if name.blank?
      sibling.tournament_entries.where("lower(btrim(name)) = ?", name.downcase).first
    end
  end
end
