class Api::PushSubscriptionsController < Api::BaseController
  # refresh is called from the service worker's pushsubscriptionchange
  # handler, which has no page and therefore no CSRF token. Skipping
  # verification (for this action only) keeps the real session instead of
  # null_session, so the cookie still authenticates; ownership is proven by
  # possession of a previously-registered endpoint — an unguessable
  # capability URL, the same reasoning as create's reassign-on-possession.
  skip_before_action :verify_authenticity_token, only: :refresh

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

  # APNs/FCM rotated the subscription behind our back: swap the stored row to
  # the new endpoint/keys so notifications keep flowing instead of dying on
  # ExpiredSubscription.
  def refresh
    old = PushSubscription.find_by(endpoint: params[:old_endpoint])
    # The old row is legitimately gone in the common rotation case: delivery
    # destroys rows on ExpiredSubscription before the browser ever fires
    # pushsubscriptionchange, and the event can carry no oldSubscription at
    # all. Possession can't be proven then, so accept the new subscription
    # only with a valid CSRF token (the SW fetches one from /api/session) —
    # the same same-origin proof create relies on. No proof at all → 404.
    return head :not_found unless old || csrf_token_valid?

    sub = PushSubscription.find_or_initialize_by(endpoint: params.dig(:subscription, :endpoint))
    sub.user = current_user
    sub.assign_attributes(
      p256dh: params.dig(:subscription, :keys, :p256dh),
      auth:   params.dig(:subscription, :keys, :auth)
    )
    if sub.save
      old.destroy if old && old.id != sub.id
      head :no_content
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

  # Manual CSRF check for refresh's no-old-row fallback (the action skips the
  # automatic one). Mirrors verify_authenticity_token's semantics, including
  # being a pass when forgery protection is globally off (tests).
  def csrf_token_valid?
    !protect_against_forgery? || any_authenticity_token_valid?
  end

  def endpoint_host(endpoint)
    URI.parse(endpoint.to_s).host
  rescue URI::InvalidURIError
    nil
  end
end
