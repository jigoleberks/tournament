class Api::PushSubscriptionsController < Api::BaseController
  def create
    sub = current_user.push_subscriptions.find_or_initialize_by(endpoint: params.dig(:subscription, :endpoint))
    sub.assign_attributes(
      p256dh: params.dig(:subscription, :keys, :p256dh),
      auth:   params.dig(:subscription, :keys, :auth)
    )
    if sub.save
      render json: { id: sub.id }, status: :created
    else
      render json: { errors: sub.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    sub = current_user.push_subscriptions.find_by(endpoint: params[:endpoint])
    sub&.destroy
    head :no_content
  end
end
