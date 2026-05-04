require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "redirects to sign in when not signed in" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "renders home when signed in" do
    user = create(:user, name: "Joe")
    post session_path, params: { email: user.email }
    token = SignInToken.last
    get consume_session_path(token: token.token)
    get root_path
    assert_response :success
    assert_select "h1", ENV.fetch("APP_NAME", "Tournament")
    assert_match "Joe", response.body
  end

  test "notifications Enable button defaults to non-blue (JS swaps it on when subscribed)" do
    user = create(:user)
    post session_path, params: { email: user.email }
    get consume_session_path(token: SignInToken.last.token)
    get root_path
    assert_response :success
    assert_select "button[data-action~=?]", "push-register#enable" do |btns|
      assert_not btns.first["class"].to_s.include?("bg-blue"),
                 "Enable button should default to non-blue; the JS controller flips it to blue when the subscription is active"
    end
  end

  test "deactivated user with an existing session is signed out on next request" do
    user = create(:user)
    post session_path, params: { email: user.email }
    get consume_session_path(token: SignInToken.last.token)
    assert_equal user.id, session[:user_id]

    user.update!(deactivated_at: Time.current)
    get root_path
    assert_redirected_to new_session_path
    assert_nil session[:user_id]
  end
end
