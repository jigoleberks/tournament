class Api::PushSubscriptionsController < Api::BaseController
  def create
    sub = current_user.push_subscriptions.find_or_initialize_by(endpoint: params.dig(:subscription, :endpoint))
    sub.assign_attributes(
      p256dh: params.dig(:subscription, :keys, :p256dh),
      auth:   params.dig(:subscription, :keys, :auth)
    )
    if sub.save
      if sub.previously_new_record?
        UserEvent.record!(user: current_user, kind: :push_subscribed,
                          user_agent: request.user_agent, app_build: cookies[:app_build],
                          endpoint_host: endpoint_host(sub.endpoint))
      end
      render json: { id: sub.id }, status: :created
    else
      render json: { errors: sub.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    sub = current_user.push_subscriptions.find_by(endpoint: params[:endpoint])
    sub&.destroy
    if sub&.destroyed?
      UserEvent.record!(user: current_user, kind: :push_unsubscribed,
                        endpoint_host: endpoint_host(sub.endpoint))
    end
    head :no_content
  end

  private

  def endpoint_host(endpoint)
    URI.parse(endpoint.to_s).host
  rescue URI::InvalidURIError
    nil
  end
end
