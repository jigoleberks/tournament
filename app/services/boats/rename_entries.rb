module Boats
  # Cascades a boat rename to every TournamentEntry the boat created — across
  # every tournament it has ever fished, finished ones included. Boats exist
  # so a team's name is typed once and reused (see NearMatch); a typo fixed
  # today on the boats screen should not go on haunting a leaderboard the boat
  # already fished under the old spelling. This is a correction to the one
  # name the boat has always had, not a rewrite of that night's roster.
  #
  # Only entries still carrying the boat's PREVIOUS name are touched. An entry
  # whose name was hand-edited away from the boat (via the entry-rename form)
  # no longer reads as "the boat's name" and is left alone — the cascade would
  # otherwise silently clobber a deliberate override with no way to tell the
  # two cases apart after the fact. An entry that still matches the old name
  # exactly is presumed to still be tracking the boat.
  #
  # Linked pairs (the Wednesday Main + Side link_group) need no special
  # handling here: Boats::Enter and TournamentLinks::SyncEntry always copy
  # boat_id onto the mirrored counterpart, so both halves of a link already
  # carry boat_id and are reached by the same boat_id-keyed query.
  #
  # Broadcasting happens AFTER the rename transaction commits, not inside it —
  # see TournamentLinks::SyncEntry for the full reasoning. Placements::
  # BroadcastLeaderboard pushes a Turbo Stream frame synchronously, so
  # broadcasting mid-transaction could show connected viewers a name that a
  # later failure in the same transaction then rolls back.
  class RenameEntries
    def self.call(boat:)
      new(boat: boat).call
    end

    def initialize(boat:)
      @boat = boat
    end

    def call
      return [] unless @boat.saved_change_to_name?

      entries = renamable_entries
      return [] if entries.empty?

      ::ActiveRecord::Base.transaction do
        entries.each { |entry| entry.update!(name: @boat.name) }
      end

      broadcast(entries)
      entries
    end

    private

    # Only entries whose name is still exactly the boat's old name — anything
    # else was deliberately retyped and is left alone (see class comment).
    def renamable_entries
      old_name = @boat.name_before_last_save
      return [] if old_name.blank?
      ::TournamentEntry.where(boat_id: @boat.id, name: old_name).to_a
    end

    def broadcast(entries)
      tournaments = ::Tournament.where(id: entries.map(&:tournament_id).uniq).index_by(&:id)
      entries.group_by(&:tournament_id).each do |tournament_id, group|
        ::Placements::BroadcastLeaderboard.call(
          tournament: tournaments.fetch(tournament_id), changed_entry_ids: group.map(&:id)
        )
      end
    end
  end
end
