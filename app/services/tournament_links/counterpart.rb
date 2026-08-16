module TournamentLinks
  # Single source of the counterpart-matching rule shared by SyncEntry and
  # RemoveEntry: same boat_id when the entry has one, else same name compared
  # case-insensitively after stripping. Kept in exactly one place because the
  # two services must never drift apart — if RemoveEntry's matching rule ever
  # diverged from SyncEntry's, RemoveEntry could destroy an entry SyncEntry
  # would never have adopted as its counterpart.
  module Counterpart
    def self.find(entry:, sibling:)
      if entry.boat_id
        by_boat = sibling.tournament_entries.find_by(boat_id: entry.boat_id)
        return by_boat if by_boat
      end
      name = entry.name.to_s.strip
      return nil if name.blank?
      sibling.tournament_entries.where("lower(btrim(name)) = ?", name.downcase).first
    end
  end
end
