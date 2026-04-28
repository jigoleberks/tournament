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
end
