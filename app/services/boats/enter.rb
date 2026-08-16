module Boats
  # Enters a saved boat into a tournament: one entry named after the boat, with
  # the captain aboard by default, mirrored across any link group. Idempotent —
  # tapping the same boat twice returns the entry that already exists rather
  # than creating a second one.
  class Enter
    def self.call(tournament:, boat:, user_ids: nil)
      new(tournament: tournament, boat: boat, user_ids: user_ids).call
    end

    def initialize(tournament:, boat:, user_ids:)
      @tournament = tournament
      @boat = boat
      @user_ids = (user_ids || [boat.captain_user_id]).map(&:to_i).uniq
    end

    def call
      existing = @tournament.tournament_entries.find_by(boat_id: @boat.id)
      return existing if existing

      entry = nil
      ::Tournament.transaction do
        entry = @tournament.tournament_entries.create!(name: @boat.name, boat: @boat)
        @user_ids.each { |uid| entry.tournament_entry_members.create!(user_id: uid) }
      end

      if @tournament.backfill_late_entrants?
        ::Tournaments::BackfillEntrantCatches.call(
          tournament: @tournament, users: ::User.where(id: @user_ids).to_a
        )
      end

      ::TournamentLinks::SyncEntry.call(entry: entry)
      notify(entry)
      ::Placements::BroadcastLeaderboard.call(tournament: @tournament, changed_entry_ids: [entry.id])
      entry
    end

    private

    def notify(entry)
      @user_ids.each do |uid|
        ::DeliverPushNotificationJob.perform_later(
          user_id: uid,
          title: @tournament.name,
          body: "You've been entered into #{@tournament.name}.",
          url: "/tournaments/#{@tournament.id}",
          tournament_id: @tournament.id
        )
      end
    end
  end
end
