require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    sign_in_as(@user)
  end

  test "PATCH /me updates length_unit to centimeters" do
    patch me_path, params: { user: { length_unit: "centimeters" } }
    assert_equal "centimeters", @user.reload.length_unit
  end

  test "PATCH /me rejects invalid length_unit" do
    patch me_path, params: { user: { length_unit: "feet" } }
    assert_equal "inches", @user.reload.length_unit
  end

  test "PATCH /me as JSON updates length_unit and returns 204" do
    patch me_path, params: { user: { length_unit: "centimeters" } }, as: :json
    assert_response :no_content
    assert_equal "centimeters", @user.reload.length_unit
  end

  test "PATCH /me as JSON rejects invalid length_unit with 422" do
    patch me_path, params: { user: { length_unit: "feet" } }, as: :json
    assert_response :unprocessable_entity
    assert_equal "inches", @user.reload.length_unit
    assert_includes JSON.parse(response.body)["errors"].join(" "), "Length unit"
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
