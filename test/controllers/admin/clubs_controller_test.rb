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

  test "admin clubs index shows View link to foreign-club hub" do
    other_club = create(:club, name: "Northtown Anglers")
    sign_in_as(@admin)
    get admin_clubs_path
    assert_response :success
    assert_includes response.body, admin_club_path(other_club)
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

  test "club hub renders the four stat counts" do
    foreign = create(:club, name: "Northtown Anglers")
    create(:user, club: foreign, role: :member)
    create(:user, club: foreign, role: :member)
    t1 = create(:tournament, club: foreign, starts_at: 2.days.ago, ends_at: 2.days.from_now)
    create(:tournament, club: foreign, starts_at: 10.days.ago, ends_at: 5.days.ago)
    create(:catch, user: foreign.members.first, captured_at_device: 1.day.ago)

    sign_in_as(@admin)
    get admin_club_path(foreign)
    assert_response :success

    # Stat labels
    assert_includes response.body, "Members"
    assert_includes response.body, "Tournaments"
    assert_includes response.body, "Active"
    assert_includes response.body, "Catches"

    # Stat values: 2 members, 2 tournaments, 1 active, 1 catch.
    # Scope to the stat-value div class so this doesn't match other "1"/"2"s on the page.
    assert_select ".text-3xl", text: "2", count: 2   # members + tournaments tiles
    assert_select ".text-3xl", text: "1", count: 2   # active + catches tiles
  end

  test "club hub renders section cards linking to each sub-resource" do
    foreign = create(:club, name: "Northtown Anglers")
    sign_in_as(@admin)
    get admin_club_path(foreign)
    assert_response :success

    assert_select "a[href=?]", admin_club_tournaments_path(foreign),         text: /Tournaments/
    assert_select "a[href=?]", admin_club_members_path(foreign),             text: /Members/
    assert_select "a[href=?]", admin_club_catches_path(foreign),             text: /Catches/
    assert_select "a[href=?]", admin_club_tournament_templates_path(foreign), text: /Templates/
    assert_select "a[href=?]", admin_club_rules_path(foreign),               text: /Rules/
  end

  test "clubs index links each row to the club hub and omits the invite button" do
    foreign = create(:club, name: "Northtown Anglers")
    sign_in_as(@admin)
    get admin_clubs_path
    assert_response :success

    # Row's name and View button both point at the hub
    assert_select "a[href=?]", admin_club_path(foreign), text: /Northtown Anglers/
    assert_select "a[href=?]", admin_club_path(foreign), text: /View/

    # No more "Invite member" row action; no direct link to new-member
    assert_select "a[href=?]", new_admin_club_member_path(foreign), count: 0
    refute_includes response.body, "Invite member"
  end

  test "hub itself does not show a back-to-club banner link" do
    foreign = create(:club, name: "Northtown Anglers")
    sign_in_as(@admin)
    get admin_club_path(foreign)
    assert_response :success
    assert_select "a", text: /Back to club/, count: 0
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
