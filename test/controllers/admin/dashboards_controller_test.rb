require "test_helper"

class Admin::DashboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host_club    = create(:club, name: "Host Anglers")
    @other_club   = create(:club, name: "Northtown Anglers")
    @admin     = create(:user, club: @host_club, admin: true, role: :organizer)
    @organizer = create(:user, club: @host_club, role: :organizer)
    @member    = create(:user, club: @host_club, role: :member)
  end

  test "member is forbidden" do
    sign_in_as(@member)
    get admin_root_path
    assert_response :forbidden
  end

  test "organizer can view dashboard" do
    sign_in_as(@organizer)
    get admin_root_path
    assert_response :success
  end

  test "non-admin organizer does NOT see site-wide stats tiles" do
    sign_in_as(@organizer)
    get admin_root_path
    refute_includes response.body, "Total clubs"
    refute_includes response.body, "Active tournaments"
  end

  test "admin sees site-wide stats tiles with values" do
    create(:tournament, club: @other_club, starts_at: 1.day.ago, ends_at: 1.day.from_now)
    sign_in_as(@admin)
    get admin_root_path
    assert_response :success
    assert_includes response.body, "Total clubs"
    assert_includes response.body, "Active members"
    assert_includes response.body, "Active tournaments"
    assert_includes response.body, "Catches last 7 days"
    # Two clubs exist; scope the count match to the "Total clubs" tile.
    assert_select "div.p-5", text: /Total clubs\s*2/
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
