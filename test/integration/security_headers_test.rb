require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "responses include frame-ancestors 'none' to block clickjacking" do
    get new_session_path
    assert_response :success
    csp = response.headers["Content-Security-Policy"].to_s
    assert_includes csp, "frame-ancestors 'none'"
  end
end
