module Leaderboards
  class BroadcastReveal
    def self.call(tournament:)
      leaderboard = Leaderboards::Build.call(tournament: tournament)
      Turbo::StreamsChannel.broadcast_replace_to(
        "tournament:#{tournament.id}:leaderboard:reveal",
        target: "leaderboard",
        # Route through the same partial selector BroadcastLeaderboard uses so a
        # Tagged tournament's reveal renders the ticket-count board, not the
        # standard length leaderboard.
        partial: Placements::BroadcastLeaderboard.partial_for(tournament),
        locals: {
          leaderboard: leaderboard,
          tournament: tournament,
          viewer_scope: Leaderboards::ViewerScope.full
        }
      )
    end
  end
end
