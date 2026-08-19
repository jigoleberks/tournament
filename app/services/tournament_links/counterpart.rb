module TournamentLinks
  # Single source of the counterpart-matching rule shared by SyncEntry and
  # RemoveEntry: same boat_id when the entry has one; else same name compared
  # case-insensitively after stripping (current name, then — if the entry was
  # just renamed — its pre-rename name); else, for SyncEntry only, an exact
  # crew-set match against a blank-named sibling entry (see match_by_crew).
  # Kept in exactly one place because the two services must never drift apart
  # — if RemoveEntry's matching rule ever diverged from SyncEntry's,
  # RemoveEntry could destroy an entry SyncEntry would never have adopted as
  # its counterpart.
  module Counterpart
    # allow_crew_match defaults OFF and is not exposed as a positional arg on
    # purpose: RemoveEntry calls Counterpart.find with no opinion on it and
    # must stay stuck with boat/name matching only — the crew tier is a
    # best-effort *adoption* heuristic for SyncEntry (which only ever
    # creates/updates), and letting a destructive caller pick it up, even by
    # future accident, would mean a wrong match hard-deletes a real entry's
    # catch placements via `dependent: :destroy` instead of silently no-oping.
    def self.find(entry:, sibling:, allow_crew_match: false)
      if entry.boat_id
        by_boat = sibling.tournament_entries.find_by(boat_id: entry.boat_id)
        return by_boat if by_boat
      end

      match_by_name(sibling, entry.name) ||
        match_by_name(sibling, rename_fallback(entry)) ||
        (allow_crew_match ? match_by_crew(sibling, entry) : nil)
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
    #
    # Deliberately narrow: only a blank-named sibling entry is a candidate
    # (a named entry is never up for adoption here — that's what the name
    # tiers above are for), and the source's crew must match a candidate's
    # crew EXACTLY, not just overlap. "A crew member can only be entered once
    # per tournament" (TournamentEntryMember#user_not_already_in_tournament)
    # only guarantees at most one sibling entry per USER, not per crew SET —
    # an overlap match on a shared angler could silently adopt a stranger's
    # entry, overwrite its name/boat, and eject its other members as if they
    # no longer belonged (see sync_members). Exact-set matching against a
    # nameless candidate is what makes this actually unambiguous. `order(:id)`
    # keeps any residual multi-candidate tie deterministic rather than
    # picking up whatever order Postgres happens to return.
    def self.match_by_crew(sibling, entry)
      wanted = entry.tournament_entry_members.pluck(:user_id).sort
      return nil if wanted.empty?

      sibling.tournament_entries
        .where("btrim(coalesce(name, '')) = ''")
        .order(:id)
        .find { |candidate| candidate.tournament_entry_members.pluck(:user_id).sort == wanted }
    end
    private_class_method :match_by_crew
  end
end
