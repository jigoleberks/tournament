require "test_helper"

class Tournaments::TeammatesAcrossTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
  end

  def active_team_tournament(name:)
    create(:tournament, club: @club, name: name, mode: :team,
                        starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
  end

  def enter(tournament, *users)
    entry = create(:tournament_entry, tournament: tournament)
    users.each { |u| create(:tournament_entry_member, tournament_entry: entry, user: u) }
    entry
  end

  test "returns the user's teammates across active team tournaments, sorted by name" do
    zed  = create(:user, club: @club, name: "Zed")
    abby = create(:user, club: @club, name: "Abby")
    t1 = active_team_tournament(name: "Cup One")
    enter(t1, @user, zed)
    t2 = active_team_tournament(name: "Cup Two")
    enter(t2, @user, abby)

    result = Tournaments::TeammatesAcross.call(user: @user, club: @club)
    assert_equal %w[Abby Zed], result.map(&:name)
  end

  test "de-duplicates a teammate the user shares two tournaments with" do
    mate = create(:user, club: @club, name: "Boatmate")
    t1 = active_team_tournament(name: "Cup One")
    enter(t1, @user, mate)
    t2 = active_team_tournament(name: "Cup Two")
    enter(t2, @user, mate)

    result = Tournaments::TeammatesAcross.call(user: @user, club: @club)
    assert_equal [mate.id], result.map(&:id)
  end

  test "returns empty when the user has no team teammates" do
    solo = create(:tournament, club: @club, mode: :solo,
                               starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    enter(solo, @user)
    assert_empty Tournaments::TeammatesAcross.call(user: @user, club: @club)
  end
end
