Rails.application.config.session_store :cookie_store,
  # v2 key invalidates pre-#44 host-only cookies that would otherwise shadow
  # the new subdomain-scoped cookie and break sign-in for returning users.
  key: "_tournament_session_v2",
  expire_after: 30.days,
  same_site: :lax,
  secure: Rails.env.production?,
  # Share the session cookie across subdomains so signing in on the bare
  # domain also signs you into admin.<APP_HOST> (and vice versa). Without
  # this, the laptop admin subdomain has its own cookie jar and bounces
  # signed-in users back to /session/new.
  domain: :all
