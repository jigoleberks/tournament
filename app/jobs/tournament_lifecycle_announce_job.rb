class TournamentLifecycleAnnounceJob < ApplicationJob
  queue_as :default

  def perform(tournament_id:, kind:)
    tournament = Tournament.find(tournament_id)
    body = kind == "started" ? "#{tournament.name} just started." : "#{tournament.name} has ended."
    tournament.tournament_entries.includes(:users).each do |entry|
      entry.users.each do |user|
        DeliverPushNotificationJob.perform_later(
          user_id: user.id, title: tournament.name, body: body,
          url: "/tournaments/#{tournament.id}", tournament_id: tournament.id
        )
      end
    end
  end
end
