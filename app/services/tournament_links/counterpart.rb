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

      match_by_name(sibling, entry.name) || match_by_name(sibling, rename_fallback(entry))
    end

    def self.match_by_name(sibling, name)
      name = name.to_s.strip
      return nil if name.blank?
      sibling.tournament_entries.where("lower(btrim(name)) = ?", name.downcase).first
    end
    private_class_method :match_by_name

    # A boat-less entry is matched purely by name. If `entry` was just
    # renamed (same in-memory object, not reloaded), the counterpart in the
    # sibling still carries the OLD name — matching on the new name alone
    # would miss it and mint a duplicate, which then fails the
    # already-entered-in-this-tournament validation when its crew is synced.
    # Falling back to the pre-rename name lets a rename update the existing
    # counterpart instead.
    def self.rename_fallback(entry)
      return nil unless entry.respond_to?(:saved_change_to_name?) && entry.saved_change_to_name?
      entry.name_before_last_save
    end
    private_class_method :rename_fallback
  end
end
