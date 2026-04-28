class InvitationMailer < ApplicationMailer
  def welcome(token)
    @token = token
    @url = consume_session_url(token: token.token)
    mail(to: token.user.email, subject: "Welcome to #{ENV.fetch('APP_NAME', 'Tournament')}")
  end
end
