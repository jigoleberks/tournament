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
end
