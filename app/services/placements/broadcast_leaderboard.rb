module Placements
  class BroadcastLeaderboard
    # Manual verification on the VM: with two browsers signed in viewing the same tournament,
    # log a catch in one — the other's leaderboard should update without reload.
    # For a blind tournament, only the broadcaster's own team's row should update on the
    # other browser; the broadcaster's screen should show their own row updated.
    # For a tagged tournament, partial_for routes to tagged_leaderboard so the
    # broadcast carries the ticket-count UI; DrawTaggedWinner also re-broadcasts
    # after a draw so the winner banner appears live.
    # changed_entry_ids (bingo only): when the caller knows which entries actually
    # changed, only those per-angler cards are rebroadcast. nil means "unknown" —
    # rebroadcast every card (safe default for callers like add/drop-member).
    def self.call(tournament:, leaderboard: nil, changed_entry_ids: nil)
      leaderboard ||= Leaderboards::Build.call(tournament: tournament)

      if tournament.format_bingo?
        broadcast_bingo(tournament, leaderboard, changed_entry_ids)
        return
      end

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

    def self.partial_for(tournament)
      tournament.format_tagged? ? "tournaments/tagged_leaderboard" : "tournaments/leaderboard"
    end

    def self.broadcast_full(tournament, leaderboard)
      Turbo::StreamsChannel.broadcast_replace_to(
        "tournament:#{tournament.id}:leaderboard:full",
        target: "leaderboard",
        partial: partial_for(tournament),
        locals: {
          leaderboard: leaderboard,
          tournament: tournament,
          viewer_scope: Leaderboards::ViewerScope.full
        }
      )
    end

    def self.broadcast_entry(tournament, leaderboard, entry_id)
      Turbo::StreamsChannel.broadcast_replace_to(
        "tournament:#{tournament.id}:leaderboard:entry:#{entry_id}",
        target: "leaderboard",
        partial: partial_for(tournament),
        locals: {
          leaderboard: leaderboard,
          tournament: tournament,
          viewer_scope: Leaderboards::ViewerScope::Scope.new(visibility: :own_entry_only, entry_id: entry_id)
        }
      )
    end

    def self.broadcast_bingo(tournament, leaderboard, changed_entry_ids = nil)
      Turbo::StreamsChannel.broadcast_replace_to(
        "tournament:#{tournament.id}:leaderboard:full",
        target: "leaderboard",
        partial: "tournaments/bingo_leaderboard",
        locals: { leaderboard: leaderboard, tournament: tournament }
      )
      cards = leaderboard
      cards = cards.select { |row| changed_entry_ids.include?(row[:entry].id) } if changed_entry_ids
      cards.each do |row|
        Turbo::StreamsChannel.broadcast_replace_to(
          "bingo_card:#{tournament.id}:#{row[:entry].id}",
          target: "bingo_card",
          partial: "tournaments/bingo_card",
          locals: { tournament: tournament, result: row[:result] }
        )
      end
    end

    def self.broadcast_reveal_full(tournament, leaderboard)
      Turbo::StreamsChannel.broadcast_replace_to(
        "tournament:#{tournament.id}:leaderboard:reveal",
        target: "leaderboard",
        partial: partial_for(tournament),
        locals: {
          leaderboard: leaderboard,
          tournament: tournament,
          viewer_scope: Leaderboards::ViewerScope.full
        }
      )
    end
  end
end
