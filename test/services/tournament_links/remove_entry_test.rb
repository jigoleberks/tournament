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

  test "does not destroy a crew-sharing sibling entry when there is no boat or name match" do
    entry = create(:tournament_entry, tournament: @main, name: "Stratos")
    entry.tournament_entry_members.create!(user: @kurtis)

    # Blank-named, no boat, but shares a crew member — the shape SyncEntry's
    # crew tier would adopt. RemoveEntry must not: it stays on boat/name
    # only, since a wrong match here hard-deletes a real entry's placements.
    crew_sharing = create(:tournament_entry, tournament: @side)
    crew_sharing.tournament_entry_members.create!(user: @kurtis)

    assert_equal 0, TournamentLinks::RemoveEntry.call(entry: entry)
    assert TournamentEntry.exists?(crew_sharing.id)
  end
end
