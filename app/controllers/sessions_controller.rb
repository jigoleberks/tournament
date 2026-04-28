class SessionsController < ApplicationController
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

  def destroy
    sign_out!
    redirect_to new_session_path
  end
end
