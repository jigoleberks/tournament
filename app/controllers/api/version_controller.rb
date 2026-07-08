class Api::VersionController < Api::BaseController
  # Live build id for the Pre-trip "App version" check. Lives under /api/ so the
  # service worker passes it straight to the network (never cached), letting a
  # re-test discover that the server has moved past the build the phone loaded.
  def show
    render json: { build: ::AppVersion.current }
  end
end
