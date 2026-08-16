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
      return [] if @entry.boat_id.nil? && @entry.name.to_s.strip.blank?

      siblings.map { |sibling| sync_into(sibling) }
    end

    private

    def sync_into(sibling)
      counterpart = find_counterpart(sibling) || sibling.tournament_entries.new
      counterpart.boat_id = @entry.boat_id
      counterpart.name = @entry.name
      created = counterpart.new_record?
      counterpart.save!

      sync_members(counterpart)

      if created && sibling.backfill_late_entrants?
        ::Tournaments::BackfillEntrantCatches.call(
          tournament: sibling, users: ::User.where(id: source_user_ids).to_a
        )
      end

      ::Placements::BroadcastLeaderboard.call(
        tournament: sibling, changed_entry_ids: [counterpart.id]
      )
      counterpart
    end

    def find_counterpart(sibling)
      if @entry.boat_id
        by_boat = sibling.tournament_entries.find_by(boat_id: @entry.boat_id)
        return by_boat if by_boat
      end
      name = @entry.name.to_s.strip
      return nil if name.blank?
      sibling.tournament_entries.where("lower(btrim(name)) = ?", name.downcase).first
    end

    def sync_members(counterpart)
      wanted = source_user_ids
      present = counterpart.tournament_entry_members.pluck(:user_id)

      (present - wanted).each do |user_id|
        member = counterpart.tournament_entry_members.find_by(user_id: user_id)
        ::Catches::DropMemberFromEntry.call(entry: counterpart, user: member.user) if member
      end

      (wanted - present).each do |user_id|
        counterpart.tournament_entry_members.create!(user_id: user_id)
      end
    end

    def source_user_ids
      @source_user_ids ||= @entry.tournament_entry_members.pluck(:user_id)
    end
  end
end
