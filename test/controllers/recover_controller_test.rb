require "test_helper"

class RecoverControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Joe")
  end

  test "redirects to sign in when not signed in" do
    get "/recover"
    assert_redirected_to new_session_path
  end

  test "404s when the recovery tool is disabled" do
    sign_in_as(@user)
    get "/recover"
    assert_response :not_found
  end

  test "renders when the recovery tool is enabled" do
    @club.update!(recovery_tool_enabled: true)
    sign_in_as(@user)
    get "/recover"
    assert_response :success
    assert_select "div[data-controller=?]", "recover"
    assert_select "ul[data-recover-target=?]", "list"
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
