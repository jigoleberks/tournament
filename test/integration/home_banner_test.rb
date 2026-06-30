require "test_helper"

class HomeBannerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club, name: "Banner Club")
    @member = create(:user, club: @club, role: :member, name: "Banner Bob")
    @membership = @member.club_memberships.find_by!(club: @club)
  end

  test "targeted member sees the banner with the chosen color" do
    @club.update!(banner_message: "Weigh-in moved to 6pm", banner_style: :alert)
    @membership.update!(show_banner: true)

    sign_in_as(@member)
    get root_path

    assert_response :success
    assert_includes response.body, "Weigh-in moved to 6pm"
    assert_includes response.body, "border-red-500/40"
  end

  test "untargeted member does not see the banner" do
    @club.update!(banner_message: "Weigh-in moved to 6pm", banner_style: :alert)
    @membership.update!(show_banner: false)

    sign_in_as(@member)
    get root_path

    assert_response :success
    assert_not_includes response.body, "Weigh-in moved to 6pm"
  end

  test "blank message hides the banner even for a targeted member" do
    @club.update!(banner_message: nil, banner_style: :info)
    @membership.update!(show_banner: true)

    sign_in_as(@member)
    get root_path

    assert_response :success
    assert_not_includes response.body, "border-yellow-500/40"
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
