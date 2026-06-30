require "test_helper"

class Admin::Clubs::BannersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @home_club = create(:club, name: "Admin Home FC")
    @admin     = create(:user, club: @home_club, admin: true)
    @member    = create(:user, club: @home_club, role: :member)

    @target_club = create(:club, name: "Target FC")
    @alice = create(:user, club: @target_club, role: :member, name: "Alice")
    @bob   = create(:user, club: @target_club, role: :member, name: "Bob")
    @alice_m = @alice.club_memberships.find_by!(club: @target_club)
    @bob_m   = @bob.club_memberships.find_by!(club: @target_club)
  end

  test "non-admin member is forbidden" do
    sign_in_as(@member)
    get edit_admin_club_banner_path(@target_club)
    assert_response :forbidden
  end

  test "admin sees the editor" do
    sign_in_as(@admin)
    get edit_admin_club_banner_path(@target_club)
    assert_response :success
    assert_includes response.body, "Alice"
    assert_includes response.body, "Bob"
  end

  test "update saves message, style, and only the selected members" do
    sign_in_as(@admin)
    patch admin_club_banner_path(@target_club), params: {
      club: { banner_message: "Meeting Friday", banner_style: "good" },
      member_ids: [@alice.id]
    }
    assert_redirected_to admin_club_path(@target_club)

    @target_club.reload
    assert_equal "Meeting Friday", @target_club.banner_message
    assert_equal "good", @target_club.banner_style
    assert_equal true,  @alice_m.reload.show_banner
    assert_equal false, @bob_m.reload.show_banner
  end

  test "update with no members selected clears all targeting" do
    @alice_m.update!(show_banner: true)
    sign_in_as(@admin)
    patch admin_club_banner_path(@target_club), params: {
      club: { banner_message: "Hi", banner_style: "info" }
    }
    assert_equal false, @alice_m.reload.show_banner
    assert_equal false, @bob_m.reload.show_banner
  end

  test "update does not touch another club's memberships" do
    other_member = create(:user, club: @home_club, role: :member)
    other_m = other_member.club_memberships.find_by!(club: @home_club)
    other_m.update!(show_banner: true)

    sign_in_as(@admin)
    patch admin_club_banner_path(@target_club), params: {
      club: { banner_message: "x", banner_style: "info" },
      member_ids: [@alice.id]
    }
    assert_equal true, other_m.reload.show_banner
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
