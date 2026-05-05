class TournamentLifecycleAnnounceJob < ApplicationJob
  queue_as :default

  def perform(tournament_id:, kind:)
    tournament = Tournament.find(tournament_id)

    if kind == "ended"
      return if tournament.lifecycle_ended_announced_at.present?
      return if tournament.ends_at && tournament.ends_at > Time.current
      tournament.update_columns(lifecycle_ended_announced_at: Time.current)
    end

    body = if kind == "ended" && tournament.blind_leaderboard?
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
  end
end
