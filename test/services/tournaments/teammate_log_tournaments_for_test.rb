require "test_helper"

class Tournaments::TeammateLogTournamentsForTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
  end

  def active_team_tournament(name: "Team Cup")
    create(:tournament, club: @club, name: name, mode: :team,
                        starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
  end

  def enter(tournament, *users)
    entry = create(:tournament_entry, tournament: tournament)
    users.each { |u| create(:tournament_entry_member, tournament_entry: entry, user: u) }
    entry
  end

  test "includes active team tournaments where the user has a teammate" do
    t = active_team_tournament
    enter(t, @user, create(:user, club: @club))
    assert_equal [t.id], Tournaments::TeammateLogTournamentsFor.call(user: @user).map(&:id)
  end

  test "excludes solo tournaments" do
    t = create(:tournament, club: @club, mode: :solo,
                            starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    enter(t, @user)
    assert_empty Tournaments::TeammateLogTournamentsFor.call(user: @user)
  end

  test "excludes team tournaments where the user is the only member" do
    t = active_team_tournament
    enter(t, @user)
    assert_empty Tournaments::TeammateLogTournamentsFor.call(user: @user)
  end

  test "excludes team tournaments the user is not entered in" do
    t = active_team_tournament
    enter(t, create(:user, club: @club), create(:user, club: @club))
    assert_empty Tournaments::TeammateLogTournamentsFor.call(user: @user)
  end
end
