require "test_helper"

class TournamentLinks::JoinTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @main = create(:tournament, club: @club, mode: :team, name: "Main")
    @side = create(:tournament, club: @club, mode: :team, name: "Side")
    @kurtis = create(:user, club: @club, name: "Kurtis Sanguin")
    @nate = create(:user, club: @club, name: "Nate Rosengren")
    @boat = create(:boat, club: @club, name: "Majestic Red", captain: @kurtis)
  end

  test "assigns a shared link_group_id to both tournaments" do
    TournamentLinks::Join.call(tournament: @main, other: @side)
    assert @main.reload.link_group_id.present?
    assert_equal @main.link_group_id, @side.reload.link_group_id
  end

  test "back-fills an entry that exists only on one side onto the other" do
    entry = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    entry.tournament_entry_members.create!(user: @kurtis)

    TournamentLinks::Join.call(tournament: @main, other: @side)

    mirrored = @side.tournament_entries.sole
    assert_equal "Majestic Red", mirrored.name
    assert_equal [@kurtis], mirrored.users
  end

  test "does not drop crew that's present on one side but missing on the other -- back-fill is a union" do
    # Side already has "Majestic Red" with a fuller crew than Main. Linking
    # from Main must not use Main's (smaller) crew as the source of truth
    # and prune Nate off Side's entry.
    main_entry = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    main_entry.tournament_entry_members.create!(user: @kurtis)

    side_entry = create(:tournament_entry, tournament: @side, name: "Majestic Red", boat: @boat)
    side_entry.tournament_entry_members.create!(user: @kurtis)
    side_entry.tournament_entry_members.create!(user: @nate)

    TournamentLinks::Join.call(tournament: @main, other: @side)

    assert_equal [@kurtis, @nate].sort_by(&:id), side_entry.reload.users.sort_by(&:id),
                 "Nate must still be on Side's entry after linking"
    assert_equal [@kurtis, @nate].sort_by(&:id), main_entry.reload.users.sort_by(&:id),
                 "Main should have picked up Nate too -- the back-fill is a union of both rosters"
  end

  test "does not drop a catch's placement when the back-fill leaves the crew member seated" do
    walleye = create(:species, name: "Walleye")
    create(:scoring_slot, tournament: @side, species: walleye, slot_count: 2)

    main_entry = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    main_entry.tournament_entry_members.create!(user: @kurtis)

    side_entry = create(:tournament_entry, tournament: @side, name: "Majestic Red", boat: @boat)
    side_entry.tournament_entry_members.create!(user: @kurtis)
    side_entry.tournament_entry_members.create!(user: @nate)
    nate_catch = create(:catch, user: @nate, species: walleye,
                        length_inches: 18, captured_at_device: 30.minutes.ago)
    Catches::PlaceInSlots.call(catch: nate_catch)
    assert CatchPlacement.exists?(catch_id: nate_catch.id, tournament_entry_id: side_entry.id, active: true)

    TournamentLinks::Join.call(tournament: @main, other: @side)

    assert CatchPlacement.exists?(catch_id: nate_catch.id, tournament_entry_id: side_entry.id, active: true),
           "Nate's placement on Side must survive the link"
  end

  test "adopts an existing link_group_id from either side rather than minting a new one" do
    group = SecureRandom.uuid
    @main.update!(link_group_id: group)

    TournamentLinks::Join.call(tournament: @main, other: @side)

    assert_equal group, @side.reload.link_group_id
  end

  test "rolls back the whole link when a crew member can't be added on the other side" do
    create(:tournament_judge, tournament: @side, user: @nate)

    main_entry = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    main_entry.tournament_entry_members.create!(user: @kurtis)
    main_entry.tournament_entry_members.create!(user: @nate)

    assert_raises(ActiveRecord::RecordInvalid) do
      TournamentLinks::Join.call(tournament: @main, other: @side)
    end
    assert_nil @main.reload.link_group_id
    assert_nil @side.reload.link_group_id
    assert_empty @side.tournament_entries.reload
  end

  # Join wraps SyncEntry in a transaction of its own, which turns SyncEntry's
  # own transaction into a no-op nested block — so SyncEntry's "broadcast only
  # after commit" discipline has to reach the OUTER commit, not its own.
  # Majestic Red mirrors cleanly and would have broadcast immediately;
  # Nate's Boat then raises and rolls the entire link back, leaving viewers
  # holding a row for an entry that no longer exists, with nothing to correct
  # it. Nothing may go out over the wire until Join itself commits.
  test "broadcasts nothing when a later entry rolls the whole link back" do
    create(:tournament_judge, tournament: @side, user: @nate)

    clean = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    clean.tournament_entry_members.create!(user: @kurtis)
    doomed = create(:tournament_entry, tournament: @main, name: "Nate's Boat")
    doomed.tournament_entry_members.create!(user: @nate)

    seen = nil
    assert_raises(ActiveRecord::RecordInvalid) do
      with_broadcast_spy do |calls|
        seen = calls
        TournamentLinks::Join.call(tournament: @main, other: @side)
      end
    end

    assert_empty seen, "a rolled-back link must not have broadcast the mirrored row"
    assert_nil @main.reload.link_group_id
    assert_empty @side.tournament_entries.reload
  end

  test "broadcasts the back-filled entries once the link commits" do
    entry = create(:tournament_entry, tournament: @main, name: "Majestic Red", boat: @boat)
    entry.tournament_entry_members.create!(user: @kurtis)

    broadcasts = with_broadcast_spy { TournamentLinks::Join.call(tournament: @main, other: @side) }

    assert_includes broadcasts, @side.id
  end
end
