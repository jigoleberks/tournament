require "test_helper"

class Admin::ClubsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club, name: "BS Phishing Family")
    @admin = create(:user, club: @club, admin: true)
    @organizer = create(:user, club: @club, role: :organizer)
    @member = create(:user, club: @club, role: :member)
  end

  test "signed-out user cannot access" do
    get admin_clubs_path
    assert_redirected_to new_session_path
  end

  test "member is forbidden" do
    sign_in_as(@member)
    get admin_clubs_path
    assert_response :forbidden
  end

  test "organizer without admin flag is forbidden" do
    sign_in_as(@organizer)
    get admin_clubs_path
    assert_response :forbidden
  end

  test "admin can list clubs" do
    create(:club, name: "Northtown Anglers")
    sign_in_as(@admin)
    get admin_clubs_path
    assert_response :success
    assert_includes response.body, "BS Phishing Family"
    assert_includes response.body, "Northtown Anglers"
  end

  test "admin can create a club" do
    sign_in_as(@admin)
    assert_difference "Club.count", 1 do
      post admin_clubs_path, params: { club: { name: "Lakeside Crew" } }
    end
    assert_redirected_to admin_clubs_path
    assert_equal "Lakeside Crew", Club.last.name
  end

  test "create with blank name re-renders new with 422" do
    sign_in_as(@admin)
    assert_no_difference "Club.count" do
      post admin_clubs_path, params: { club: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "create with duplicate name re-renders new with 422" do
    sign_in_as(@admin)
    assert_no_difference "Club.count" do
      post admin_clubs_path, params: { club: { name: "BS Phishing Family" } }
    end
    assert_response :unprocessable_entity
  end

  test "admin can rename a club" do
    sign_in_as(@admin)
    patch admin_club_path(@club), params: { club: { name: "BS Phishing Families" } }
    assert_redirected_to admin_clubs_path
    assert_equal "BS Phishing Families", @club.reload.name
  end

  test "non-admin cannot create" do
    sign_in_as(@organizer)
    assert_no_difference "Club.count" do
      post admin_clubs_path, params: { club: { name: "Sneaky Club" } }
    end
    assert_response :forbidden
  end

  test "non-admin cannot rename" do
    sign_in_as(@organizer)
    patch admin_club_path(@club), params: { club: { name: "Hijacked" } }
    assert_response :forbidden
    assert_equal "BS Phishing Family", @club.reload.name
  end

  test "admin clubs index shows View link to foreign-club tournaments" do
    other_club = create(:club, name: "Northtown Anglers")
    sign_in_as(@admin)
    get admin_clubs_path
    assert_response :success
    assert_includes response.body, admin_club_tournaments_path(other_club)
  end

  test "admin can view the club hub" do
    foreign = create(:club, name: "Northtown Anglers")
    sign_in_as(@admin)
    get admin_club_path(foreign)
    assert_response :success
    assert_includes response.body, "Northtown Anglers"
  end

  test "non-admin cannot view the club hub" do
    foreign = create(:club, name: "Northtown Anglers")
    sign_in_as(@organizer)
    get admin_club_path(foreign)
    assert_response :forbidden
  end

  test "signed-out user cannot view the club hub" do
    foreign = create(:club, name: "Northtown Anglers")
    get admin_club_path(foreign)
    assert_redirected_to new_session_path
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
