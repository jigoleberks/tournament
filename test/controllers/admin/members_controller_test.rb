require "test_helper"

class Admin::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club, name: "BS Phishing Family")
    @admin = create(:user, club: @club, admin: true, role: :organizer)
  end

  test "authenticated request stamps last_seen_at on current_user" do
    @admin.update_columns(last_seen_at: nil)
    sign_in_as(@admin)
    get admin_members_path
    assert_response :success
    assert_not_nil @admin.reload.last_seen_at
  end

  test "signed-out request to a public page does not stamp anyone" do
    target = create(:user, club: @club, last_seen_at: nil)
    get new_session_path
    assert_response :success
    assert_nil target.reload.last_seen_at
  end

  test "renders Never badge for users with no last_seen_at" do
    create(:user, club: @club, name: "Unclaimed Carl", last_seen_at: nil)
    sign_in_as(@admin)
    get admin_members_path
    assert_response :success
    assert_includes response.body, "Unclaimed Carl"
    assert_match %r{Unclaimed Carl.*Never}m, response.body
  end

  test "renders relative time for users with a last_seen_at" do
    freeze_time do
      create(:user, club: @club, name: "Active Alice", last_seen_at: 3.days.ago)
      sign_in_as(@admin)
      get admin_members_path
      assert_response :success
      assert_match %r{Active Alice.*3 days ago}m, response.body
    end
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
