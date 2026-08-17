require "test_helper"

class BroadcastBoatRenameJobTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @kurtis = create(:user, club: @club, name: "Kurtis Sanguin")
    @boat = create(:boat, club: @club, name: "Majestic Red", captain: @kurtis)
  end

  test "broadcasts once per distinct tournament, not once per entry" do
    group = SecureRandom.uuid
    main = create(:tournament, club: @club, mode: :team, name: "Main", link_group_id: group)
    side = create(:tournament, club: @club, mode: :team, name: "Side", link_group_id: group)
    other = create(:tournament, club: @club, mode: :team, name: "Other",
                    starts_at: 3.days.ago, ends_at: 2.days.ago)
    e1 = create(:tournament_entry, tournament: main, name: "Majestic Red", boat: @boat)
    e2 = create(:tournament_entry, tournament: side, name: "Majestic Red", boat: @boat)
    e3 = create(:tournament_entry, tournament: other, name: "Majestic Red", boat: @boat)

    tournament_ids = with_broadcast_spy do
      BroadcastBoatRenameJob.perform_now(entry_ids: [ e1.id, e2.id, e3.id ])
    end

    assert_equal [ main.id, side.id, other.id ].sort, tournament_ids.sort
    assert_equal 3, tournament_ids.size
  end

  test "passes only the affected tournament's own entry ids as changed_entry_ids" do
    t1 = create(:tournament, club: @club, mode: :team, name: "T1")
    t2 = create(:tournament, club: @club, mode: :team, name: "T2")
    e1 = create(:tournament_entry, tournament: t1, name: "Majestic Red", boat: @boat)
    e2a = create(:tournament_entry, tournament: t2)
    e2b = create(:tournament_entry, tournament: t2)

    seen = []
    original = Placements::BroadcastLeaderboard.method(:call)
    Placements::BroadcastLeaderboard.define_singleton_method(:call) do |tournament:, changed_entry_ids:, **|
      seen << [ tournament.id, changed_entry_ids ]
    end
    begin
      BroadcastBoatRenameJob.perform_now(entry_ids: [ e1.id, e2a.id, e2b.id ])
    ensure
      Placements::BroadcastLeaderboard.define_singleton_method(:call, original)
    end

    t1_call = seen.find { |tid, _| tid == t1.id }
    t2_call = seen.find { |tid, _| tid == t2.id }
    assert_equal [ e1.id ], t1_call.last
    assert_equal [ e2a.id, e2b.id ].sort, t2_call.last.sort
  end

  test "does nothing when none of the given entries exist any more" do
    tournament_ids = with_broadcast_spy do
      BroadcastBoatRenameJob.perform_now(entry_ids: [ 0 ])
    end
    assert_empty tournament_ids
  end
end
