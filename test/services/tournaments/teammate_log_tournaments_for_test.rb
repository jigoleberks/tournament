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
    assert_equal [t.id], Tournaments::TeammateLogTournamentsFor.call(user: @user, club: @club).map(&:id)
  end

  test "excludes solo tournaments" do
    t = create(:tournament, club: @club, mode: :solo,
                            starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    enter(t, @user)
    assert_empty Tournaments::TeammateLogTournamentsFor.call(user: @user, club: @club)
  end

  test "excludes team tournaments where the user is the only member" do
    t = active_team_tournament
    enter(t, @user)
    assert_empty Tournaments::TeammateLogTournamentsFor.call(user: @user, club: @club)
  end

  test "excludes team tournaments the user is not entered in" do
    t = active_team_tournament
    enter(t, create(:user, club: @club), create(:user, club: @club))
    assert_empty Tournaments::TeammateLogTournamentsFor.call(user: @user, club: @club)
  end

  test "returns only the given club's tournaments when user belongs to two clubs with team tournaments" do
    # @user is already in @club. Create a second club and join it.
    other_club = create(:club)
    create(:club_membership, user: @user, club: other_club)

    # Active team tournament in @club with a teammate.
    t_a = active_team_tournament(name: "Club A Cup")
    enter(t_a, @user, create(:user, club: @club))

    # Active team tournament in other_club with a teammate.
    t_b = create(:tournament, club: other_club, name: "Club B Cup", mode: :team,
                              starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    enter(t_b, @user, create(:user, club: other_club))

    result = Tournaments::TeammateLogTournamentsFor.call(user: @user, club: @club)
    assert_equal [t_a.id], result.map(&:id),
                 "expected only club A's tournament; got #{result.map(&:id).inspect}"
  end
end
