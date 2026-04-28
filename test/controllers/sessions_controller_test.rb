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
end
