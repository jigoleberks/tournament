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

      match_by_name(sibling, entry.name) ||
        match_by_name(sibling, rename_fallback(entry)) ||
        match_by_crew(sibling, entry)
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

    # Last resort for a boat-less entry once both name checks miss — which
    # happens after a blank-name hop: the sibling counterpart was carried to
    # a blank name (see SyncEntry), so once the source is renamed away from
    # blank, name_before_last_save is ALSO blank and can't lead back to it.
    # A crew member can only be entered once per tournament (see
    # TournamentEntryMember#user_not_already_in_tournament), so "does the
    # sibling already have an entry containing one of this entry's current
    # members" is an unambiguous identity check that survives name history
    # loss entirely.
    def self.match_by_crew(sibling, entry)
      user_ids = entry.tournament_entry_members.pluck(:user_id)
      return nil if user_ids.empty?
      sibling.tournament_entries.joins(:tournament_entry_members)
        .where(tournament_entry_members: { user_id: user_ids }).first
    end
    private_class_method :match_by_crew
  end
end
