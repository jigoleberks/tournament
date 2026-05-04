# Be sure to restart your server when you modify this file.
#
# Minimal CSP: deny framing to prevent clickjacking. Other directives
# (script-src, style-src, etc.) are intentionally left unset — locking
# them down with Hotwire + importmap + Tailwind needs nonce work that's
# out of scope for this change.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.frame_ancestors :none
  end
end
