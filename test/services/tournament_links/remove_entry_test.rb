require "test_helper"

class TournamentLinks::RemoveEntryTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    group = SecureRandom.uuid
    @main = create(:tournament, club: @club, mode: :team, link_group_id: group)
    @side = create(:tournament, club: @club, mode: :team, link_group_id: group)
    @kurtis = create(:user, club: @club, name: "Kurtis Sanguin")
    @boat = create(:boat, club: @club, name: "Majestic Red", captain: @kurtis)
  end

  test "destroys the counterpart in the linked tournament" do
    entry = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    entry.tournament_entry_members.create!(user: @kurtis)
    TournamentLinks::SyncEntry.call(entry: entry)

    assert_difference "TournamentEntry.count", -1 do
      assert_equal 1, TournamentLinks::RemoveEntry.call(entry: entry)
    end
    assert_empty @side.tournament_entries.reload
  end

  test "returns zero when there is no counterpart" do
    entry = create(:tournament_entry, tournament: @main, name: "Stratos")
    assert_equal 0, TournamentLinks::RemoveEntry.call(entry: entry)
  end
end
