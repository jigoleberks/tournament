require "test_helper"

class TournamentEntryMemberTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @tournament = create(:tournament, club: @club)
    @user = create(:user, club: @club)
    @entry = create(:tournament_entry, tournament: @tournament)
  end

  test "a judge of the tournament can't be entered in it" do
    create(:tournament_judge, tournament: @tournament, user: @user)

    member = build(:tournament_entry_member, tournament_entry: @entry, user: @user)

    assert_not member.valid?
    assert_includes member.errors[:user], "is judging this tournament and can't be entered in it"
  end

  test "a non-judge can be entered" do
    member = build(:tournament_entry_member, tournament_entry: @entry, user: @user)

    assert member.valid?
  end
end
