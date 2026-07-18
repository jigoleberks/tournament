# Drain preflight for the offline sync client. One cheap GET answers, before
# any multi-MB photo body is uploaded: (1) is this session still signed in
# (401 here halts the drain — previously each 401 was discovered only AFTER a
# full photo upload), (2) a fresh CSRF token (the precached /offline shell has
# none, and a bfcache-restored page can hold a stale one), and (3) who is
# signed in, so the queue can refuse to drain another user's catches.
class Api::SessionsController < Api::BaseController
  def show
    render json: { user_id: current_user.id, csrf_token: form_authenticity_token }
  end
end
