require "test_helper"

class Boats::RenameEntriesTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @kurtis = create(:user, club: @club, name: "Kurtis Sanguin")
    @boat = create(:boat, club: @club, name: "Majestic red", captain: @kurtis)
  end

  test "renames a finished tournament's entry that still matches the boat's old name" do
    finished = create(:tournament, club: @club, mode: :team,
                       starts_at: 2.days.ago, ends_at: 1.day.ago)
    entry = create(:tournament_entry, tournament: finished, name: "Majestic red", boat: @boat)

    @boat.update!(name: "Majestic Red")
    Boats::RenameEntries.call(boat: @boat)

    assert_equal "Majestic Red", entry.reload.name
  end

  test "renames every entry across every tournament the boat has fished" do
    t1 = create(:tournament, club: @club, mode: :team, starts_at: 3.days.ago, ends_at: 2.days.ago)
    t2 = create(:tournament, club: @club, mode: :team, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    e1 = create(:tournament_entry, tournament: t1, name: "Majestic red", boat: @boat)
    e2 = create(:tournament_entry, tournament: t2, name: "Majestic red", boat: @boat)

    @boat.update!(name: "Majestic Red")
    Boats::RenameEntries.call(boat: @boat)

    assert_equal "Majestic Red", e1.reload.name
    assert_equal "Majestic Red", e2.reload.name
  end

  test "does not touch entries when only the captain changes" do
    other_captain = create(:user, club: @club, name: "Other Captain")
    tournament = create(:tournament, club: @club, mode: :team)
    entry = create(:tournament_entry, tournament: tournament, name: "Majestic red", boat: @boat)

    @boat.update!(captain_user_id: other_captain.id)
    result = Boats::RenameEntries.call(boat: @boat)

    assert_empty result
    assert_equal "Majestic red", entry.reload.name
  end

  test "does not rename an entry whose name was deliberately edited away from the boat" do
    tournament = create(:tournament, club: @club, mode: :team)
    entry = create(:tournament_entry, tournament: tournament, name: "Majestic red - DQ'd", boat: @boat)

    @boat.update!(name: "Majestic Red")
    Boats::RenameEntries.call(boat: @boat)

    assert_equal "Majestic red - DQ'd", entry.reload.name
  end

  test "covers a linked pair by boat_id alone, with no extra syncing needed" do
    group = SecureRandom.uuid
    main = create(:tournament, club: @club, mode: :team, name: "Main", link_group_id: group)
    side = create(:tournament, club: @club, mode: :team, name: "Side", link_group_id: group)
    main_entry = create(:tournament_entry, tournament: main, name: "Majestic red", boat: @boat)
    side_entry = create(:tournament_entry, tournament: side, name: "Majestic red", boat: @boat)

    @boat.update!(name: "Majestic Red")
    Boats::RenameEntries.call(boat: @boat)

    assert_equal "Majestic Red", main_entry.reload.name
    assert_equal "Majestic Red", side_entry.reload.name
  end

  test "broadcasts once per affected tournament, not once per entry" do
    group = SecureRandom.uuid
    main = create(:tournament, club: @club, mode: :team, name: "Main", link_group_id: group)
    side = create(:tournament, club: @club, mode: :team, name: "Side", link_group_id: group)
    other = create(:tournament, club: @club, mode: :team, name: "Other",
                    starts_at: 3.days.ago, ends_at: 2.days.ago)
    create(:tournament_entry, tournament: main, name: "Majestic red", boat: @boat)
    create(:tournament_entry, tournament: side, name: "Majestic red", boat: @boat)
    create(:tournament_entry, tournament: other, name: "Majestic red", boat: @boat)

    @boat.update!(name: "Majestic Red")
    tournament_ids = with_broadcast_spy do
      Boats::RenameEntries.call(boat: @boat)
    end

    assert_equal [main.id, side.id, other.id].sort, tournament_ids.sort
    assert_equal 3, tournament_ids.size
  end

  test "does nothing and does not broadcast when the boat has no matching entries" do
    @boat.update!(name: "Majestic Red")
    tournament_ids = with_broadcast_spy do
      assert_empty Boats::RenameEntries.call(boat: @boat)
    end
    assert_empty tournament_ids
  end

  test "does nothing when the boat's name did not change" do
    tournament = create(:tournament, club: @club, mode: :team)
    entry = create(:tournament_entry, tournament: tournament, name: "Majestic red", boat: @boat)

    tournament_ids = with_broadcast_spy do
      # Saving with the same name is a no-op change; saved_change_to_name? is false.
      @boat.update!(name: "Majestic red")
      assert_empty Boats::RenameEntries.call(boat: @boat)
    end

    assert_empty tournament_ids
    assert_equal "Majestic red", entry.reload.name
  end

  test "rolls back every rename and broadcasts nothing when one entry fails to save" do
    t1 = create(:tournament, club: @club, mode: :team, name: "T1")
    t2 = create(:tournament, club: @club, mode: :team, name: "T2")
    entry1 = create(:tournament_entry, tournament: t1, name: "Majestic red", boat: @boat)
    entry2 = create(:tournament_entry, tournament: t2, name: "Majestic red", boat: @boat)

    @boat.update!(name: "Majestic Red")

    # Force the SAME rows the service will load to include one whose update!
    # raises, so the whole rename transaction rolls back. If broadcasting ever
    # moved inside the transaction (the bug TournamentLinks::SyncEntry guards
    # against — see its own pinning test), entry1's frame would already be on
    # the wire by the time entry2's raise unwound the write.
    loaded = ::TournamentEntry.where(boat_id: @boat.id, name: "Majestic red").to_a
    failing = loaded.find { |e| e.id == entry2.id }
    failing.define_singleton_method(:update!) { |*| raise ::ActiveRecord::RecordInvalid.new(self) }

    broadcast_calls = 0
    original_broadcast = Placements::BroadcastLeaderboard.method(:call)
    Placements::BroadcastLeaderboard.define_singleton_method(:call) { |**| broadcast_calls += 1 }

    expected_boat_id = @boat.id
    original_where = ::TournamentEntry.method(:where)
    ::TournamentEntry.define_singleton_method(:where) do |*args, **kwargs|
      kwargs[:boat_id] == expected_boat_id ? loaded : original_where.call(*args, **kwargs)
    end

    begin
      assert_raises(::ActiveRecord::RecordInvalid) do
        Boats::RenameEntries.call(boat: @boat)
      end
    ensure
      ::TournamentEntry.define_singleton_method(:where, original_where)
      Placements::BroadcastLeaderboard.define_singleton_method(:call, original_broadcast)
    end

    assert_equal 0, broadcast_calls, "a rolled-back rename must not have broadcast entry1's phantom new name"
    assert_equal "Majestic red", entry1.reload.name
  end
end
