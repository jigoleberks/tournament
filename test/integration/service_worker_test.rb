require "test_helper"

class ServiceWorkerTest < ActionDispatch::IntegrationTest
  IPHONE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) " \
              "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"

  test "GET /service-worker.js serves the script with a versioned cache key" do
    get "/service-worker.js", headers: { "HTTP_USER_AGENT" => IPHONE_UA }
    assert_response :success
    assert_match %r{\Atext/javascript}, response.media_type
    # Cache key must be derived from AppVersion (git SHA or fallback) so each
    # deploy invalidates the install-time and runtime caches.
    assert_match(/const CACHE = "shell-#{Regexp.escape(AppVersion.current)}"/, response.body)
  end

  test "service worker response sets no-cache so browsers re-check on every visit" do
    get "/service-worker.js", headers: { "HTTP_USER_AGENT" => IPHONE_UA }
    assert_includes response.headers["Cache-Control"].to_s, "no-cache"
  end
end
