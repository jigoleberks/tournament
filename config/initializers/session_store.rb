Rails.application.config.session_store :cookie_store,
  key: "_tournament_session",
  expire_after: 30.days,
  same_site: :lax,
  secure: Rails.env.production?,
  # Share the session cookie across subdomains so signing in on the bare
  # domain also signs you into admin.<APP_HOST> (and vice versa). Without
  # this, the laptop admin subdomain has its own cookie jar and bounces
  # signed-in users back to /session/new.
  domain: :all
