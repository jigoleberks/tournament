require "test_helper"

class Admin::RulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @member = create(:user, club: @club, role: :member)
  end

  test "index requires organizer role" do
    sign_in_as(@member)
    get admin_rules_path
    assert_response :forbidden
  end

  test "organizer can view the index" do
    sign_in_as(@organizer)
    get admin_rules_path
    assert_response :success
  end

  test "set_active_season flips the club's active season" do
    sign_in_as(@organizer)
    assert @club.reload.active_rules_season_open_water?

    post set_active_season_admin_rules_path, params: { season: "ice" }
    assert_redirected_to admin_rules_path
    assert @club.reload.active_rules_season_ice?
  end

  test "set_active_season rejects unknown season values" do
    sign_in_as(@organizer)
    post set_active_season_admin_rules_path, params: { season: "summer" }
    assert_response :unprocessable_entity
    assert @club.reload.active_rules_season_open_water?
  end

  test "set_active_season requires organizer role" do
    sign_in_as(@member)
    post set_active_season_admin_rules_path, params: { season: "ice" }
    assert_response :forbidden
    assert @club.reload.active_rules_season_open_water?
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
