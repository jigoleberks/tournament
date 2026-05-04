require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = create(:user, email: "joe@example.com") }

  test "POST /session creates a token and emails it" do
    assert_difference "SignInToken.count", 1 do
      assert_emails 1 do
        post session_path, params: { email: "joe@example.com" }
      end
    end
    assert_redirected_to "/session/check_email"
  end

  test "POST /session is silent on unknown email (no enumeration)" do
    assert_no_difference "SignInToken.count" do
      assert_no_emails do
        post session_path, params: { email: "nobody@example.com" }
      end
    end
    assert_redirected_to "/session/check_email"
  end

  test "GET consume signs the user in for a valid token" do
    token = SignInToken.issue!(user: @user)
    get consume_session_path(token: token.token)
    assert_redirected_to root_path
    assert_equal @user.id, session[:user_id]
  end

  test "GET consume rejects an expired token" do
    token = SignInToken.issue!(user: @user)
    token.update!(expires_at: 1.minute.ago)
    get consume_session_path(token: token.token)
    assert_redirected_to new_session_path
    assert_nil session[:user_id]
  end

  test "POST /session/code signs in with a matching email and code" do
    code = SignInToken.issue_code!(user: @user)
    post code_session_path, params: { email: @user.email, code: code.token }
    assert_redirected_to root_path
    assert_equal @user.id, session[:user_id]
  end

  test "POST /session/code re-renders with an alert on bad code" do
    SignInToken.issue_code!(user: @user)
    post code_session_path, params: { email: @user.email, code: "00000000" }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  test "GET consume rejects a deactivated user" do
    token = SignInToken.issue!(user: @user)
    @user.update!(deactivated_at: Time.current)
    get consume_session_path(token: token.token)
    assert_redirected_to new_session_path
    assert_nil session[:user_id]
  end

  test "POST /session/code rejects a deactivated user" do
    code = SignInToken.issue_code!(user: @user)
    @user.update!(deactivated_at: Time.current)
    post code_session_path, params: { email: @user.email, code: code.token }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  test "consume rotates the session id to defeat fixation" do
    get new_session_path
    fixed_id = session.id&.to_s
    token = SignInToken.issue!(user: @user)
    get consume_session_path(token: token.token)
    assert_equal @user.id, session[:user_id]
    rotated_id = session.id&.to_s
    assert rotated_id.present?
    assert_not_equal fixed_id, rotated_id
  end
end
