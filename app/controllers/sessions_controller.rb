class SessionsController < ApplicationController
  rate_limit to: 5, within: 1.minute,
             only: :create,
             with: -> { redirect_to "/session/check_email" }

  rate_limit to: 10, within: 3.minutes,
             only: :submit_code,
             by: -> { "code-attempt:#{request.remote_ip}:#{params[:email].to_s.downcase.strip}" },
             with: -> { redirect_to code_session_path, alert: "Too many attempts. Try again shortly." }

  def new; end

  def create
    user = User.find_by(email: params[:email])
    if user
      token = SignInToken.issue!(user: user)
      SignInMailer.magic_link(token).deliver_later
    end
    redirect_to "/session/check_email"
  end

  def consume
    user = SignInToken.consume!(params[:token])
    if user
      sign_in!(user)
      redirect_to root_path, notice: "Welcome, #{user.name}"
    else
      redirect_to new_session_path, alert: "That sign-in link is invalid or expired."
    end
  end

  def check_email; end

  def code; end

  def submit_code
    user = SignInToken.consume_code!(email: params[:email], code: params[:code])
    if user
      sign_in!(user)
      redirect_to root_path, notice: "Welcome, #{user.name}"
    else
      flash.now[:alert] = "That email and code don't match, or the code has expired."
      render :code, status: :unprocessable_entity
    end
  end

  def destroy
    sign_out!
    redirect_to new_session_path
  end
end
