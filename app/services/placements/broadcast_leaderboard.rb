module Placements
  class BroadcastLeaderboard
    # Broadcasts a Turbo Stream replace of the leaderboard partial to the tournament's channel.
    # Manual verification on the VM: with two browsers signed in viewing the same tournament,
    # log a catch in one — the other's leaderboard should update without reload.
    def self.call(tournament:)
      leaderboard = Leaderboards::Build.call(tournament: tournament)
      Turbo::StreamsChannel.broadcast_replace_to(
        "tournament:#{tournament.id}:leaderboard",
        target: "leaderboard",
        partial: "tournaments/leaderboard",
        locals: { leaderboard: leaderboard, tournament: tournament }
      )
    end
  end
end
