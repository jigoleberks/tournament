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

  test "backfills a newly created counterpart when the sibling allows late entrants" do
    @side.update!(backfill_late_entrants: true)
    walleye = create(:species, name: "Walleye")
    create(:scoring_slot, tournament: @side, species: walleye, slot_count: 2)
    already_logged = create(:catch, user: @kurtis, species: walleye,
                            length_inches: 20, captured_at_device: 30.minutes.ago)

    entry = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    entry.tournament_entry_members.create!(user: @kurtis)

    mirrored = TournamentLinks::SyncEntry.call(entry: entry).first

    assert CatchPlacement.exists?(
      catch_id: already_logged.id, tournament_id: @side.id,
      tournament_entry_id: mirrored.id, active: true
    ), "Kurtis's already-logged catch should be backfilled into the new counterpart"
  end

  test "backfills catches for crew added to an already-mirrored counterpart" do
    @side.update!(backfill_late_entrants: true)
    walleye = create(:species, name: "Walleye")
    create(:scoring_slot, tournament: @side, species: walleye, slot_count: 2)

    entry = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    entry.tournament_entry_members.create!(user: @kurtis)
    TournamentLinks::SyncEntry.call(entry: entry)

    nate_catch = create(:catch, user: @nate, species: walleye,
                        length_inches: 18, captured_at_device: 30.minutes.ago)
    entry.tournament_entry_members.create!(user: @nate)
    mirrored = TournamentLinks::SyncEntry.call(entry: entry).first

    assert CatchPlacement.exists?(
      catch_id: nate_catch.id, tournament_id: @side.id,
      tournament_entry_id: mirrored.id, active: true
    ), "Nate's catch, logged before he joined the Side's mirrored entry, should backfill on sync"
  end

  test "broadcasts once per sibling after a successful sync" do
    entry = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    entry.tournament_entry_members.create!(user: @kurtis)

    broadcast_calls = 0
    original = Placements::BroadcastLeaderboard.method(:call)
    Placements::BroadcastLeaderboard.define_singleton_method(:call) do |**kwargs|
      broadcast_calls += 1
      original.call(**kwargs)
    end
    begin
      TournamentLinks::SyncEntry.call(entry: entry)
      assert_equal 1, broadcast_calls, "exactly one sibling (Side) should be broadcast to, exactly once"
    ensure
      Placements::BroadcastLeaderboard.define_singleton_method(:call, original)
    end
  end

  test "rolls back the whole sync and broadcasts nothing when a later sibling raises" do
    third = create(:tournament, club: @club, mode: :team, name: "Third", link_group_id: @main.link_group_id)
    # Nate judges Third (not Side), so mirroring him into a Third counterpart
    # raises TournamentEntryMember's user_not_a_judge validation. Side has no
    # such conflict — if broadcasting happened inside the transaction (the
    # round-1 bug), Side's counterpart would already have gone out over Turbo
    # Streams by the time Third's raise rolls the whole write back.
    create(:tournament_judge, tournament: third, user: @nate)

    entry = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    entry.tournament_entry_members.create!(user: @kurtis)
    entry.tournament_entry_members.create!(user: @nate)

    # Force a deterministic processing order (Side first, then Third) so this
    # test doesn't depend on the row order of an unordered SQL query.
    side, third_sibling = @side, third
    @main.define_singleton_method(:linked_tournaments) { [side, third_sibling] }

    broadcast_calls = 0
    original = Placements::BroadcastLeaderboard.method(:call)
    Placements::BroadcastLeaderboard.define_singleton_method(:call) do |**kwargs|
      broadcast_calls += 1
      original.call(**kwargs)
    end
    begin
      assert_no_difference [ "TournamentEntry.count", "TournamentEntryMember.count" ] do
        assert_raises(ActiveRecord::RecordInvalid) do
          TournamentLinks::SyncEntry.call(entry: entry)
        end
      end
      assert_equal 0, broadcast_calls, "a rolled-back sync must not have broadcast Side's phantom row"
    ensure
      Placements::BroadcastLeaderboard.define_singleton_method(:call, original)
    end
    assert_empty @side.tournament_entries.reload
    assert_empty third.tournament_entries.reload
  end
end
