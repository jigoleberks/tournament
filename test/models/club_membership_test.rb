require "test_helper"

class ClubMembershipTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @user = create(:user)
  end

  test "default role is member" do
    membership = ClubMembership.create!(user: @user, club: @club)
    assert membership.member?
  end

  test "role can be organizer" do
    membership = ClubMembership.create!(user: @user, club: @club, role: :organizer)
    assert membership.organizer?
  end

  test "user cannot have two memberships in the same club" do
    ClubMembership.create!(user: @user, club: @club, role: :member)
    duplicate = ClubMembership.new(user: @user, club: @club, role: :organizer)
    assert_not duplicate.valid?
  end

  test "user can have memberships in different clubs" do
    other_club = create(:club)
    ClubMembership.create!(user: @user, club: @club, role: :member)
    second = ClubMembership.new(user: @user, club: other_club, role: :organizer)
    assert second.valid?
  end

  test "active scope excludes deactivated memberships" do
    active = create(:club_membership, user: @user, club: @club)
    deactivated = create(:club_membership, user: @user, club: create(:club), deactivated_at: Time.current)
    assert_includes ClubMembership.active, active
    assert_not_includes ClubMembership.active, deactivated
  end

  test "deactivated? reflects deactivated_at" do
    membership = create(:club_membership, user: @user, club: @club)
    assert_not membership.deactivated?
    membership.update!(deactivated_at: Time.current)
    assert membership.deactivated?
  end
end
