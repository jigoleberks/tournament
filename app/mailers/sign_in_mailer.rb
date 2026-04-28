class SignInMailer < ApplicationMailer
  def magic_link(token)
    @token = token
    @url = consume_session_url(token: token.token)
    mail(to: token.user.email, subject: "Sign in to #{ENV.fetch('APP_NAME', 'Tournament')}")
  end
end
