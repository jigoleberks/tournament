class Api::PushSubscriptionsController < Api::BaseController
  def create
    endpoint = params.dig(:subscription, :endpoint)
    # Look the endpoint up UNSCOPED: on a shared phone the browser returns the
    # same push endpoint to whoever is signed in, so a row left by the previous
    # user would otherwise 422 forever while they keep receiving this device's
    # notifications. Possession of the endpoint is proof enough — reassign it.
    sub = PushSubscription.find_or_initialize_by(endpoint: endpoint)
    newly_registered = sub.new_record? || sub.user_id != current_user.id
    sub.user = current_user
    sub.assign_attributes(
      p256dh: params.dig(:subscription, :keys, :p256dh),
      auth:   params.dig(:subscription, :keys, :auth)
    )
    if sub.save
      if newly_registered
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
