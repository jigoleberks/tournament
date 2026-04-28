class DeliverPushNotificationJob < ApplicationJob
  queue_as :default

  def perform(user_id:, title:, body:, url:, tournament_id:)
    user = User.find(user_id)
    tournament = Tournament.find_by(id: tournament_id)
    user.push_subscriptions.each do |sub|
      next if sub.muted?
      next if tournament && sub.muted_for?(tournament)

      begin
        WebPush.payload_send(
          message: { title: title, body: body, url: url }.to_json,
          endpoint: sub.endpoint,
          p256dh: sub.p256dh,
          auth: sub.auth,
          vapid: { subject: VAPID[:subject], public_key: VAPID[:public_key], private_key: VAPID[:private_key] }
        )
      rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
        sub.destroy
      rescue WebPush::ResponseError => e
        Rails.logger.warn("push delivery failed: #{e.message}")
      end
    end
  end
end
