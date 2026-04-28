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
end
