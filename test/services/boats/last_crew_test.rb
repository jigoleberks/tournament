require "test_helper"

class Boats::LastCrewTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @galen = create(:user, club: @club, name: "Galen Patterson")
    @troy = create(:user, club: @club, name: "Troy Patterson")
    @boat = create(:boat, club: @club, name: "Team Patterson", captain: @galen)
    @last_week = create(:tournament, club: @club, mode: :team,
                        starts_at: 8.days.ago, ends_at: 8.days.ago + 3.hours)
    @tonight = create(:tournament, club: @club, mode: :team,
                      starts_at: 1.hour.from_now, ends_at: 4.hours.from_now)
  end

  test "returns the crew from the boat's most recent earlier tournament" do
    entry = create(:tournament_entry, tournament: @last_week, name: "Team Patterson", boat: @boat)
    entry.tournament_entry_members.create!(user: @galen)
    entry.tournament_entry_members.create!(user: @troy)

    assert_equal [@galen, @troy].sort_by(&:id),
                 Boats::LastCrew.call(boat: @boat, before_tournament: @tonight).sort_by(&:id)
  end

  test "returns an empty array for a boat with no history" do
    assert_empty Boats::LastCrew.call(boat: @boat, before_tournament: @tonight)
  end

  test "ignores the tournament being entered" do
    entry = create(:tournament_entry, tournament: @tonight, name: "Team Patterson", boat: @boat)
    entry.tournament_entry_members.create!(user: @galen)
    assert_empty Boats::LastCrew.call(boat: @boat, before_tournament: @tonight)
  end
end
