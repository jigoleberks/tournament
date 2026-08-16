require "test_helper"

class TournamentLinks::SyncEntryTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    group = SecureRandom.uuid
    @main = create(:tournament, club: @club, mode: :team, name: "Main", link_group_id: group)
    @side = create(:tournament, club: @club, mode: :team, name: "Side", link_group_id: group)
    @kurtis = create(:user, club: @club, name: "Kurtis Sanguin")
    @nate = create(:user, club: @club, name: "Nate Rosengren")
    @boat = create(:boat, club: @club, name: "Majestic Red", captain: @kurtis)
  end

  test "creates the counterpart entry in the linked tournament" do
    entry = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    entry.tournament_entry_members.create!(user: @kurtis)

    counterparts = TournamentLinks::SyncEntry.call(entry: entry)

    assert_equal 1, counterparts.size
    mirrored = counterparts.first
    assert_equal @side, mirrored.tournament
    assert_equal "Majestic Red", mirrored.name
    assert_equal @boat, mirrored.boat
    assert_equal [@kurtis], mirrored.users
  end

  test "is idempotent - a second call creates nothing new" do
    entry = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    entry.tournament_entry_members.create!(user: @kurtis)
    TournamentLinks::SyncEntry.call(entry: entry)

    assert_no_difference "TournamentEntry.count" do
      TournamentLinks::SyncEntry.call(entry: entry)
    end
  end

  test "brings a rename across to the counterpart" do
    entry = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    entry.tournament_entry_members.create!(user: @kurtis)
    TournamentLinks::SyncEntry.call(entry: entry)

    entry.update!(name: "Majestic Red II")
    mirrored = TournamentLinks::SyncEntry.call(entry: entry).first

    assert_equal "Majestic Red II", mirrored.name
  end

  test "adds and removes crew on the counterpart" do
    entry = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    entry.tournament_entry_members.create!(user: @kurtis)
    TournamentLinks::SyncEntry.call(entry: entry)

    entry.tournament_entry_members.create!(user: @nate)
    mirrored = TournamentLinks::SyncEntry.call(entry: entry).first
    assert_equal [@kurtis, @nate].sort_by(&:id), mirrored.users.sort_by(&:id)

    entry.tournament_entry_members.find_by(user: @nate).destroy!
    mirrored = TournamentLinks::SyncEntry.call(entry: entry).first
    assert_equal [@kurtis], mirrored.users
  end

  test "matches an existing counterpart by name when there is no boat" do
    entry = create(:tournament_entry, tournament: @main, name: "Team Loos")
    entry.tournament_entry_members.create!(user: @kurtis)
    existing = create(:tournament_entry, tournament: @side, name: "team loos ")

    assert_no_difference "TournamentEntry.count" do
      TournamentLinks::SyncEntry.call(entry: entry)
    end
    assert_equal [@kurtis], existing.reload.users
  end

  test "does nothing for an unlinked tournament" do
    solo_club_tournament = create(:tournament, club: @club, mode: :team)
    entry = create(:tournament_entry, tournament: solo_club_tournament, name: "Stratos")
    assert_empty TournamentLinks::SyncEntry.call(entry: entry)
  end

  test "does nothing for an entry with no boat and no name" do
    entry = create(:tournament_entry, tournament: @main)
    entry.tournament_entry_members.create!(user: @kurtis)
    assert_empty TournamentLinks::SyncEntry.call(entry: entry)
  end
end
