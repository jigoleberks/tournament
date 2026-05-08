require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup { @club = create(:club) }

  test "requires name and email" do
    assert_not User.new(club: @club).valid?
  end

  test "email must be unique within a club" do
    create(:user, club: @club, email: "a@b.com")
    duplicate = build(:user, club: @club, email: "a@b.com")
    assert_not duplicate.valid?
  end

  test "default role is member" do
    user = create(:user, club: @club)
    assert user.member?
  end

  test "can be promoted to organizer" do
    user = create(:user, club: @club)
    user.update!(role: :organizer)
    assert user.organizer?
  end

  test "length_unit must be inches or centimeters" do
    u = build(:user, length_unit: "feet")
    assert_not u.valid?
    assert_includes u.errors.full_messages.join, "Length unit"
  end

  test "metric? reflects centimeters preference" do
    u = build(:user, length_unit: "centimeters")
    assert u.metric?
    u.length_unit = "inches"
    assert_not u.metric?
  end

  test "default is inches" do
    u = create(:user)
    assert_equal "inches", u.length_unit
  end

  test "admin? defaults to false" do
    u = create(:user, club: @club)
    assert_not u.admin?
  end

  test "admin? reflects the admin flag" do
    u = create(:user, club: @club, admin: true)
    assert u.admin?
  end

  test "organizer_in? is true only for the user's organizer membership" do
    u = create(:user, club: @club)
    other_club = create(:club)
    create(:club_membership, user: u, club: @club, role: :organizer)
    create(:club_membership, user: u, club: other_club, role: :member)
    assert u.organizer_in?(@club)
    assert_not u.organizer_in?(other_club)
  end

  test "organizer_in? ignores deactivated memberships" do
    u = create(:user, club: @club)
    create(:club_membership, user: u, club: @club, role: :organizer, deactivated_at: Time.current)
    assert_not u.organizer_in?(@club)
  end

  test "organizer_in? returns false for nil club" do
    u = create(:user, club: @club)
    assert_not u.organizer_in?(nil)
  end

  test "member_of? is true for any active membership in the club" do
    u = create(:user, club: @club)
    other_club = create(:club)
    create(:club_membership, user: u, club: @club, role: :member)
    assert u.member_of?(@club)
    assert_not u.member_of?(other_club)
  end

  test "member_of? ignores deactivated memberships" do
    u = create(:user, club: @club)
    create(:club_membership, user: u, club: @club, role: :member, deactivated_at: Time.current)
    assert_not u.member_of?(@club)
  end
end
