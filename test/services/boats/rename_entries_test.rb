require "test_helper"

class Boats::RenameEntriesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  # Boats::SeedFromHistory#apply attaches boat_id to a whole NearMatch-grouped
  # cluster of historical entries via a bare update_all — it never rewrites
  # any entry's name to the boat's chosen "newest spelling". So an entry like
  # this, straight out of a seed run, has NEVER exactly equalled the boat's
  # name — matching on exact equality would leave it permanently unfixable.
  # Matching on the same NearMatch.normalize key SeedFromHistory grouped by
  # (which also strips a leading "Team ") re-admits it.
  test "renames a seeded entry whose historical spelling never exactly matched the boat" do
    tournament = create(:tournament, club: @club, mode: :team,
                         starts_at: 3.days.ago, ends_at: 2.days.ago)
    entry = create(:tournament_entry, tournament: tournament, name: "Team Majestic Red")
    ::TournamentEntry.where(id: entry.id).update_all(boat_id: @boat.id)

    @boat.update!(name: "Majestic Red II")
    Boats::RenameEntries.call(boat: @boat)

    assert_equal "Majestic Red II", entry.reload.name
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

  test "covers a linked pair created via Boats::Enter, by boat_id alone" do
    group = SecureRandom.uuid
    main = create(:tournament, club: @club, mode: :team, name: "Main", link_group_id: group)
    side = create(:tournament, club: @club, mode: :team, name: "Side", link_group_id: group)

    main_entry = Boats::Enter.call(tournament: main, boat: @boat)
    side_entry = side.tournament_entries.sole

    # Load-bearing on SyncEntry actually copying boat_id onto the mirrored
    # counterpart — if that ever stopped, this assertion (not just the rename
    # below) would catch it, rather than the test only proving true-by-
    # construction against a hand-built fixture.
    assert_equal @boat.id, side_entry.boat_id

    @boat.update!(name: "Majestic Red")
    Boats::RenameEntries.call(boat: @boat)

    assert_equal "Majestic Red", main_entry.reload.name
    assert_equal "Majestic Red", side_entry.reload.name
  end

  test "enqueues one background broadcast job carrying every renamed entry id" do
    group = SecureRandom.uuid
    main = create(:tournament, club: @club, mode: :team, name: "Main", link_group_id: group)
    side = create(:tournament, club: @club, mode: :team, name: "Side", link_group_id: group)
    other = create(:tournament, club: @club, mode: :team, name: "Other",
                    starts_at: 3.days.ago, ends_at: 2.days.ago)
    e1 = create(:tournament_entry, tournament: main, name: "Majestic red", boat: @boat)
    e2 = create(:tournament_entry, tournament: side, name: "Majestic red", boat: @boat)
    e3 = create(:tournament_entry, tournament: other, name: "Majestic red", boat: @boat)

    @boat.update!(name: "Majestic Red")

    assert_enqueued_with(job: BroadcastBoatRenameJob) do
      Boats::RenameEntries.call(boat: @boat)
    end

    enqueued_ids = enqueued_jobs.find { |j| j["job_class"] == "BroadcastBoatRenameJob" }["arguments"].first["entry_ids"]
    assert_equal [e1.id, e2.id, e3.id].sort, enqueued_ids.sort
  end

  test "actually broadcasting the redraw does not happen inline in the request — only enqueuing does" do
    tournament = create(:tournament, club: @club, mode: :team)
    create(:tournament_entry, tournament: tournament, name: "Majestic red", boat: @boat)

    @boat.update!(name: "Majestic Red")

    tournament_ids = with_broadcast_spy do
      Boats::RenameEntries.call(boat: @boat)
    end

    assert_empty tournament_ids, "the redraw must be deferred to BroadcastBoatRenameJob, not fired inline"
  end

  test "does nothing and enqueues no job when the boat has no matching entries" do
    @boat.update!(name: "Majestic Red")
    assert_no_enqueued_jobs do
      assert_empty Boats::RenameEntries.call(boat: @boat)
    end
  end

  test "does nothing when the boat's name did not change" do
    tournament = create(:tournament, club: @club, mode: :team)
    entry = create(:tournament_entry, tournament: tournament, name: "Majestic red", boat: @boat)

    assert_no_enqueued_jobs do
      # Saving with the same name is a no-op change; saved_change_to_name? is false.
      @boat.update!(name: "Majestic red")
      assert_empty Boats::RenameEntries.call(boat: @boat)
    end

    assert_equal "Majestic red", entry.reload.name
  end

  test "rolls back every rename and enqueues no broadcast job when one entry fails to save" do
    t1 = create(:tournament, club: @club, mode: :team, name: "T1")
    t2 = create(:tournament, club: @club, mode: :team, name: "T2")
    entry1 = create(:tournament_entry, tournament: t1, name: "Majestic red", boat: @boat)
    entry2 = create(:tournament_entry, tournament: t2, name: "Majestic red", boat: @boat)

    @boat.update!(name: "Majestic Red")

    # Force the SAME rows the service will load to include one whose update!
    # raises, so the whole rename transaction rolls back. If the job were
    # ever enqueued from inside the transaction instead of after it commits,
    # this would catch it enqueuing for a write that then rolled back.
    loaded = ::TournamentEntry.where(boat_id: @boat.id).to_a
    failing = loaded.find { |e| e.id == entry2.id }
    failing.define_singleton_method(:update!) { |*| raise ::ActiveRecord::RecordInvalid.new(self) }

    expected_boat_id = @boat.id
    original_where = ::TournamentEntry.method(:where)
    ::TournamentEntry.define_singleton_method(:where) do |*args, **kwargs|
      kwargs[:boat_id] == expected_boat_id ? loaded : original_where.call(*args, **kwargs)
    end

    begin
      assert_no_enqueued_jobs do
        assert_raises(::ActiveRecord::RecordInvalid) do
          Boats::RenameEntries.call(boat: @boat)
        end
      end
    ensure
      ::TournamentEntry.define_singleton_method(:where, original_where)
    end

    assert_equal "Majestic red", entry1.reload.name
  end
end
