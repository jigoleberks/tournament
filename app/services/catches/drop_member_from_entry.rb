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
          freed.each do |p|
            p.reload
            ::Catches::PromoteBackup.call(freed_placement: p)
          end
        end
      end
      ::Placements::BroadcastLeaderboard.call(tournament: tournament)
    end
  end
end
