module Catches
  class DropMemberFromEntry
    def self.call(entry:, user:)
      new(entry: entry, user: user).call
    end

    def initialize(entry:, user:)
      @entry = entry
      @user  = user
    end

    def call
      tournament = @entry.tournament
      ActiveRecord::Base.transaction do
        @entry.lock!
        freed = @entry.catch_placements.active
                       .joins(:catch).where(catches: { user_id: @user.id }).to_a
        membership = @entry.tournament_entry_members.find_by(user_id: @user.id)
        membership&.destroy
        if freed.any?
          ::CatchPlacement.where(id: freed.map(&:id)).update_all(active: false)
          # No p.reload: the reconcile services re-query placements from the DB
          # (already updated above) and never read the in-memory p.active.
          freed.each { |p| ::Catches::ReconcileFreedSlot.call(placement: p) }
        end
      end
      # Only this entry's card changed (bingo); other anglers' cards are untouched.
      ::Placements::BroadcastLeaderboard.call(tournament: tournament, changed_entry_ids: [@entry.id])
    end
  end
end
