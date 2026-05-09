class TournamentLifecycleAnnounceJob < ApplicationJob
  queue_as :default

  def perform(tournament_id:, kind:)
    tournament = Tournament.find(tournament_id)

    if kind == "ended"
      return if tournament.lifecycle_ended_announced_at.present?
      return if tournament.ends_at && tournament.ends_at > Time.current
    end

    if kind == "ended" && tournament.format_hidden_length?
      Tournaments::RollHiddenLengthTarget.call(tournament: tournament)
    end

    body = if kind == "ended" && tournament.format_hidden_length?
      target = tournament.reload.hidden_length_target
      "Target was #{format("%.2f", target)}\" — see final standings."
    elsif kind == "ended" && tournament.blind_leaderboard?
      "Results are in, GO CHECK YOUR STANDINGS"
    elsif kind == "ended"
      "#{tournament.name} has ended."
    else
      "#{tournament.name} just started."
    end

    tournament.tournament_entries.includes(:users).each do |entry|
      entry.users.each do |user|
        DeliverPushNotificationJob.perform_later(
          user_id: user.id, title: tournament.name, body: body,
          url: "/tournaments/#{tournament.id}", tournament_id: tournament.id
        )
      end
    end

    if kind == "ended" && tournament.blind_leaderboard?
      Leaderboards::BroadcastReveal.call(tournament: tournament)
    end

    if kind == "ended"
      tournament.update_columns(lifecycle_ended_announced_at: Time.current)
    end
  end
end
