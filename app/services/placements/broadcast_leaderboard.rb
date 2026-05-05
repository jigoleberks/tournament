module Placements
  class BroadcastLeaderboard
    # Manual verification on the VM: with two browsers signed in viewing the same tournament,
    # log a catch in one — the other's leaderboard should update without reload.
    # For a blind tournament, only the broadcaster's own team's row should update on the
    # other browser; the broadcaster's screen should show their own row updated.
    def self.call(tournament:)
      leaderboard = Leaderboards::Build.call(tournament: tournament)

      if tournament.blind?(at: Time.current)
        broadcast_full(tournament, leaderboard)
        tournament.tournament_entries.pluck(:id).each do |entry_id|
          broadcast_entry(tournament, leaderboard, entry_id)
        end
      else
        broadcast_full(tournament, leaderboard)
        broadcast_reveal_full(tournament, leaderboard) if tournament.blind_leaderboard?
      end
    end

    def self.broadcast_full(tournament, leaderboard)
      Turbo::StreamsChannel.broadcast_replace_to(
        "tournament:#{tournament.id}:leaderboard:full",
        target: "leaderboard",
        partial: "tournaments/leaderboard",
        locals: {
          leaderboard: leaderboard,
          tournament: tournament,
          viewer_scope: Leaderboards::ViewerScope::Scope.new(visibility: :full, entry_id: nil)
        }
      )
    end

    def self.broadcast_entry(tournament, leaderboard, entry_id)
      Turbo::StreamsChannel.broadcast_replace_to(
        "tournament:#{tournament.id}:leaderboard:entry:#{entry_id}",
        target: "leaderboard",
        partial: "tournaments/leaderboard",
        locals: {
          leaderboard: leaderboard,
          tournament: tournament,
          viewer_scope: Leaderboards::ViewerScope::Scope.new(visibility: :own_entry_only, entry_id: entry_id)
        }
      )
    end

    def self.broadcast_reveal_full(tournament, leaderboard)
      Turbo::StreamsChannel.broadcast_replace_to(
        "tournament:#{tournament.id}:leaderboard:reveal",
        target: "leaderboard",
        partial: "tournaments/leaderboard",
        locals: {
          leaderboard: leaderboard,
          tournament: tournament,
          viewer_scope: Leaderboards::ViewerScope::Scope.new(visibility: :full, entry_id: nil)
        }
      )
    end
  end
end
