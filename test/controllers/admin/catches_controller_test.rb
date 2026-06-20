require "test_helper"

class Admin::CatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @member = create(:user, club: @club, name: "Club Carl", role: :member)
    @other_club = create(:club)
    @foreign = create(:user, club: @other_club, name: "Outsider Olive", role: :member)
    @member_catch = create(:catch, user: @member, length_inches: 22.5)
    @foreign_catch = create(:catch, user: @foreign, length_inches: 19.0)
  end

  test "non-organizer member is forbidden" do
    sign_in_as(@member)
    get admin_catches_path
    assert_response :forbidden
  end

  test "organizer sees the club's catches but not other clubs'" do
    sign_in_as(@organizer)
    get admin_catches_path
    assert_response :success
    assert_includes response.body, "Club Carl"
    refute_includes response.body, "Outsider Olive"
  end

  test "user_id filter scopes the catch list to the selected user" do
    other_member = create(:user, club: @club, name: "Other Member", role: :member)
    create(:catch, user: other_member, length_inches: 14.0)
    sign_in_as(@organizer)
    get admin_catches_path, params: { user_id: @member.id }

    assert_select "ul.grid li", minimum: 1 do
      assert_select "*", text: /Club Carl/
    end
    assert_select "ul.grid li *", text: /Other Member/, count: 0
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
