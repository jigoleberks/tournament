module Leaderboards
  class BroadcastReveal
    def self.call(tournament:)
      leaderboard = Leaderboards::Build.call(tournament: tournament)
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
