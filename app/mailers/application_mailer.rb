class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "Tournament <noreply@localhost>")
  layout "mailer"
end
