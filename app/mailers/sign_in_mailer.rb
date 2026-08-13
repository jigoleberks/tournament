class SignInMailer < ApplicationMailer
  # On iOS the emailed link opens in Safari — a separate cookie jar from the
  # installed home-screen PWA — and the token is single-use, so a standalone
  # user who taps it ends up signed in to the wrong browser with a dead link.
  # The code is their in-app path: the code screen is reachable from inside
  # the PWA and doesn't leave the shell.
  def magic_link(token, code: nil)
    @token = token
    @code = code
    @url = consume_session_url(token: token.token)
    mail(to: token.user.email, subject: "Sign in to #{ENV.fetch('APP_NAME', 'Tournament')}")
  end
end
