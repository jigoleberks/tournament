module TournamentLinks
  # Mirrors one entry into every tournament linked to its own. Used for the
  # create, rename, and crew-change paths, and to back-fill both sides when a
  # link is first made — so it must be safe to call repeatedly with no effect.
  #
  # Counterparts are matched by boat first and by normalized name second, so an
  # entry typed by hand on the Side before the link existed is adopted rather
  # than duplicated.
  class SyncEntry
    def self.call(entry:)
      new(entry: entry).call
    end

    def initialize(entry:)
      @entry = entry
    end

    def call
      siblings = @entry.tournament.linked_tournaments
      return [] if siblings.empty?
      return [] if boatless_and_never_named?

      # One transaction for the whole sync: a rejected sync (e.g. a crew member
      # who judges the sibling tournament, see TournamentEntryMember) must not
      # leave a crewless or partially-crewed phantom counterpart behind, and
      # with more than one sibling it must not leave earlier siblings synced
      # while a later one fails.
      #
      # Broadcasting happens AFTER the transaction commits, not inside it.
      # Placements::BroadcastLeaderboard pushes a Turbo Stream frame
      # synchronously (it isn't deferred to after_commit); broadcasting inside
      # the transaction would let an earlier sibling's frame reach connected
      # viewers before a later sibling's raise rolls the whole write back,
      # leaving a phantom row on screen with no row in the DB and no
      # guaranteed later event to correct it. Collecting the counterparts here
      # and broadcasting once per sibling afterward keeps every broadcast
      # truthful: it only ever reflects state that is actually committed.
      counterparts = ::ActiveRecord::Base.transaction do
        siblings.map { |sibling| sync_into(sibling) }
      end

      siblings.zip(counterparts).each do |sibling, counterpart|
        ::Placements::BroadcastLeaderboard.call(
          tournament: sibling, changed_entry_ids: [counterpart.id]
        )
      end

      counterparts
    end

    private

    # A boat-less, never-named entry (the shape a solo entry is stuck in
    # forever) has nothing to match a counterpart by, so skip it entirely —
    # that's what keeps solo tournaments a no-op. But an entry that HAD a
    # name and was just blanked out is a different case: it still has a
    # counterpart to find (via Counterpart's pre-rename name fallback, or —
    # once the entry is renamed a second time away from blank — its
    # crew-based fallback, since name_before_last_save is itself blank by
    # then) and that counterpart needs the blank carried across. Bailing
    # here instead would silently orphan the sibling with its old name/crew.
    def boatless_and_never_named?
      return false if @entry.boat_id
      return false if @entry.name.to_s.strip.present?
      !renamed_from_a_name?
    end

    def renamed_from_a_name?
      @entry.respond_to?(:saved_change_to_name?) &&
        @entry.saved_change_to_name? &&
        @entry.name_before_last_save.to_s.strip.present?
    end

    def sync_into(sibling)
      counterpart = Counterpart.find(entry: @entry, sibling: sibling) || sibling.tournament_entries.new
      counterpart.boat_id = @entry.boat_id
      counterpart.name = @entry.name
      created = counterpart.new_record?
      counterpart.save!

      added_user_ids = sync_members(counterpart)

      if sibling.backfill_late_entrants?
        # A brand-new counterpart has no prior members, so every source member
        # is "added"; keep using the full source set there in case sync_members
        # ever changes. An existing counterpart only backfills the members that
        # were just added — the ones already present were backfilled (or
        # deliberately not) whenever they first joined.
        backfill_user_ids = created ? source_user_ids : added_user_ids
        if backfill_user_ids.any?
          ::Tournaments::BackfillEntrantCatches.call(
            tournament: sibling, users: ::User.where(id: backfill_user_ids).to_a
          )
        end
      end

      counterpart
    end

    # Returns the user ids newly added to the counterpart (wanted - present).
    def sync_members(counterpart)
      wanted = source_user_ids
      present = counterpart.tournament_entry_members.pluck(:user_id)

      (present - wanted).each do |user_id|
        member = counterpart.tournament_entry_members.find_by(user_id: user_id)
        ::Catches::DropMemberFromEntry.call(entry: counterpart, user: member.user) if member
      end

      added = wanted - present
      added.each do |user_id|
        counterpart.tournament_entry_members.create!(user_id: user_id)
      end
      added
    end

    def source_user_ids
      @source_user_ids ||= @entry.tournament_entry_members.pluck(:user_id)
    end
  end
end
