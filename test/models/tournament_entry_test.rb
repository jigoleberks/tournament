require "test_helper"

class TournamentEntryTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @solo_t = create(:tournament, club: @club, mode: :solo)
    @team_t = create(:tournament, club: @club, mode: :team)
    @users = Array.new(3) { create(:user, club: @club) }
  end

  test "solo mode: exactly 1 member required" do
    entry = TournamentEntry.create!(tournament: @solo_t)
    entry.tournament_entry_members.create!(user: @users[0])
    assert entry.valid?

    too_many = entry.tournament_entry_members.build(user: @users[1])
    assert_not too_many.valid?
  end

  test "team mode: respects MAX_TEAM_MEMBERS cap" do
    cap = TournamentEntryMember::MAX_TEAM_MEMBERS
    users = Array.new(cap + 1) { create(:user, club: @club) }
    entry = TournamentEntry.create!(tournament: @team_t, name: "Big Boat")

    cap.times do |i|
      entry.tournament_entry_members.create!(user: users[i])
    end
    assert entry.valid?

    one_too_many = entry.tournament_entry_members.build(user: users[cap])
    assert_not one_too_many.valid?
    assert_includes one_too_many.errors[:base], "team is at capacity (#{cap} anglers max)"
  end

  test "an angler cannot be on two entries in the same tournament" do
    entry_a = TournamentEntry.create!(tournament: @team_t, name: "Boat A")
    entry_a.tournament_entry_members.create!(user: @users[0])

    entry_b = TournamentEntry.create!(tournament: @team_t, name: "Boat B")
    duplicate = entry_b.tournament_entry_members.build(user: @users[0])
    assert_not duplicate.valid?
  end
end
