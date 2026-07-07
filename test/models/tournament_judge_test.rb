require "test_helper"

class TournamentJudgeTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @tournament = create(:tournament, club: @club)
    @user = create(:user, club: @club)
  end

  test "a user can judge a tournament once" do
    create(:tournament_judge, tournament: @tournament, user: @user)
    duplicate = build(:tournament_judge, tournament: @tournament, user: @user)
    assert_not duplicate.valid?
  end

  test "tournament.judge_users returns judges" do
    create(:tournament_judge, tournament: @tournament, user: @user)
    assert_includes @tournament.judge_users, @user
  end

  test "a user entered in the tournament can't be made a judge of it" do
    entry = create(:tournament_entry, tournament: @tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)

    judge = build(:tournament_judge, tournament: @tournament, user: @user)

    assert_not judge.valid?
    assert_includes judge.errors[:user], "is entered in this tournament and can't judge it"
  end
end
