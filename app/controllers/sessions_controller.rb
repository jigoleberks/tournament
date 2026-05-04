class SessionsController < ApplicationController
  rate_limit to: 5, within: 1.minute,
             only: :create,
             by: -> { "link:#{params[:email].to_s.downcase.strip}" },
             with: -> { redirect_to "/session/check_email" }

  rate_limit to: 10, within: 3.minutes,
             only: :submit_code,
             by: -> { "code-attempt:#{request.remote_ip}:#{params[:email].to_s.downcase.strip}" },
             with: -> { redirect_to code_session_path, alert: "Too many attempts. Try again shortly." }

  def new; end

  def create
    email = params[:email].to_s.downcase.strip
    user = User.find_by(email: email)
    if user
      SignInToken.issue!(user: user).tap { |t| SignInMailer.magic_link(t).deliver_later }
      login_log "link_sent", email: email, ip: request.remote_ip
    else
      login_log "email_not_found", email: email, ip: request.remote_ip
    end
    redirect_to "/session/check_email"
  end

  def consume
    user = SignInToken.consume!(params[:token])
    if user
      sign_in!(user)
      login_log "link_success", email: user.email, ip: request.remote_ip
      redirect_to root_path, notice: "Welcome, #{user.name}"
    else
      login_log "link_invalid", ip: request.remote_ip
      redirect_to new_session_path, alert: "That sign-in link is invalid or expired."
    end
  end

  def check_email; end

  def code; end

  def submit_code
    email = params[:email].to_s.downcase.strip
    user = SignInToken.consume_code!(email: email, code: params[:code])
    if user
      sign_in!(user)
      login_log "code_success", email: user.email, ip: request.remote_ip
      redirect_to root_path, notice: "Welcome, #{user.name}"
    else
      login_log "code_failed", email: email, ip: request.remote_ip
      flash.now[:alert] = "That email and code don't match, or the code has expired."
      render :code, status: :unprocessable_entity
    end
  end

  def destroy
    sign_out!
    redirect_to new_session_path
  end

  private

  def login_log(outcome, email: nil, ip: nil)
    parts = { ts: Time.current.iso8601, outcome: outcome }
    parts[:email] = email if email
    parts[:ip] = ip if ip
    LOGIN_LOGGER.info(parts.map { |k, v| "#{k}=#{v}" }.join(" "))
  end
end
