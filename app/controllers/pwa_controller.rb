class PwaController < ApplicationController
  # The same-origin check on JS responses fires when content-type is text/javascript;
  # service workers are loaded by the browser itself (not a <script> include) so the
  # cross-origin-script defense is a false positive here.
  skip_forgery_protection only: :service_worker

  def manifest
    render template: "pwa/manifest", formats: [:json], content_type: "application/manifest+json"
  end

  def service_worker
    # Tell browsers to re-check the SW file every navigation rather than serving
    # a cached copy. The SW response body is tiny; the per-deploy cache key
    # bump inside it is what actually invalidates the asset cache for users.
    response.headers["Cache-Control"] = "no-cache, max-age=0, must-revalidate"
    render template: "pwa/service_worker", formats: [:js], content_type: "text/javascript"
  end
end
