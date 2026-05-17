require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup { @club = create(:club) }

  test "requires name and email" do
    assert_not User.new.valid?
  end

  test "email must be globally unique" do
    create(:user, email: "a@b.com")
    duplicate = build(:user, email: "a@b.com")
    assert_not duplicate.valid?
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
    u = create(:user)
    assert_not u.admin?
  end

  test "admin? reflects the admin flag" do
    u = create(:user, admin: true)
    assert u.admin?
  end

  test "organizer_in? is true only for the user's organizer membership" do
    other_club = create(:club)
    u = create(:user, club: @club, role: :organizer)
    create(:club_membership, user: u, club: other_club, role: :member)
    assert u.organizer_in?(@club)
    assert_not u.organizer_in?(other_club)
  end

  test "organizer_in? ignores deactivated memberships" do
    u = create(:user)
    create(:club_membership, user: u, club: @club, role: :organizer, deactivated_at: Time.current)
    assert_not u.organizer_in?(@club)
  end

  test "organizer_in? returns false for nil club" do
    u = create(:user, club: @club)
    assert_not u.organizer_in?(nil)
  end

  test "member_of? is true for any active membership in the club" do
    other_club = create(:club)
    u = create(:user, club: @club)
    assert u.member_of?(@club)
    assert_not u.member_of?(other_club)
  end

  test "member_of? ignores deactivated memberships" do
    u = create(:user)
    create(:club_membership, user: u, club: @club, role: :member, deactivated_at: Time.current)
    assert_not u.member_of?(@club)
  end

  test "touch_last_seen! writes when last_seen_at is nil" do
    u = create(:user, club: @club)
    assert_nil u.last_seen_at
    freeze_time do
      u.touch_last_seen!
      assert_equal Time.current, u.reload.last_seen_at
    end
  end

  test "touch_last_seen! writes when last_seen_at is older than the throttle window" do
    u = create(:user, club: @club, last_seen_at: 2.hours.ago)
    before = u.last_seen_at
    freeze_time do
      u.touch_last_seen!
      assert_equal Time.current, u.reload.last_seen_at
      assert_not_equal before, u.last_seen_at
    end
  end

  test "touch_last_seen! is a no-op when last_seen_at is within the throttle window" do
    recent = 5.minutes.ago
    u = create(:user, club: @club, last_seen_at: recent)
    u.touch_last_seen!
    assert_in_delta recent.to_f, u.reload.last_seen_at.to_f, 0.001
  end

  test "touch_last_seen! does not bump updated_at" do
    u = create(:user, club: @club, last_seen_at: 2.hours.ago)
    original_updated_at = u.reload.updated_at
    travel 1.minute do
      u.touch_last_seen!
      assert_equal original_updated_at, u.reload.updated_at
    end
  end
end
