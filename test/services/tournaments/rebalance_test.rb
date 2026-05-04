require "test_helper"

module Tournaments
  class RebalanceTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @t = create(:tournament, club: @club, starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
    end

    test "broadcasts the leaderboard exactly once and enqueues no push jobs" do
      broadcast_calls = 0
      with_broadcast_stub(->(tournament:) { broadcast_calls += 1 }) do
        assert_no_enqueued_jobs only: DeliverPushNotificationJob do
          Tournaments::Rebalance.call(tournament: @t)
        end
      end
      assert_equal 1, broadcast_calls
    end

    test "adding a scoring slot pulls eligible catches into the new slot" do
      user = create(:user, club: @club)
      entry = create(:tournament_entry, tournament: @t)
      member = create(:tournament_entry_member, tournament_entry: entry, user: user)
      member.update_column(:created_at, 2.hours.ago)
      big = create(:catch, user: user, species: @walleye, length_inches: 24,
                           captured_at_device: 30.minutes.ago)
      small = create(:catch, user: user, species: @walleye, length_inches: 18,
                             captured_at_device: 30.minutes.ago)
      # Slot didn't exist before — create it now and rebalance.
      create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 2)

      Tournaments::Rebalance.call(tournament: @t)

      active = @t.catch_placements.active.where(species: @walleye).order(:slot_index)
      assert_equal [big.id, small.id], active.map(&:catch_id)
      assert_equal [0, 1], active.map(&:slot_index)
    end

    test "increasing slot_count fills the new slots with the next-largest catches" do
      user = create(:user, club: @club)
      entry = create(:tournament_entry, tournament: @t)
      member = create(:tournament_entry_member, tournament_entry: entry, user: user)
      member.update_column(:created_at, 2.hours.ago)
      create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)
      catches = [24, 22, 20].map do |inches|
        c = create(:catch, user: user, species: @walleye, length_inches: inches,
                           captured_at_device: 30.minutes.ago)
        Catches::PlaceInSlots.call(catch: c)
        c
      end
      @t.scoring_slots.first.update!(slot_count: 3)

      Tournaments::Rebalance.call(tournament: @t)

      active = @t.catch_placements.active.where(species: @walleye).order(:slot_index)
      assert_equal catches.map(&:id), active.map(&:catch_id)
      assert_equal [0, 1, 2], active.map(&:slot_index)
    end

    test "decreasing slot_count deactivates the smallest active placements" do
      user = create(:user, club: @club)
      entry = create(:tournament_entry, tournament: @t)
      member = create(:tournament_entry_member, tournament_entry: entry, user: user)
      member.update_column(:created_at, 2.hours.ago)
      slot = create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 3)
      catches = [24, 22, 20].map do |inches|
        c = create(:catch, user: user, species: @walleye, length_inches: inches,
                           captured_at_device: 30.minutes.ago)
        Catches::PlaceInSlots.call(catch: c)
        c
      end
      slot.update!(slot_count: 1)

      Tournaments::Rebalance.call(tournament: @t)

      active = @t.catch_placements.active.where(species: @walleye)
      assert_equal 1, active.count
      assert_equal catches.first.id, active.first.catch_id
      assert_equal 0, active.first.slot_index
    end

    test "removing a species' scoring_slot deactivates all that species' placements" do
      user = create(:user, club: @club)
      entry = create(:tournament_entry, tournament: @t)
      member = create(:tournament_entry_member, tournament_entry: entry, user: user)
      member.update_column(:created_at, 2.hours.ago)
      slot = create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)
      c = create(:catch, user: user, species: @walleye, length_inches: 22,
                         captured_at_device: 30.minutes.ago)
      Catches::PlaceInSlots.call(catch: c)
      slot.destroy!

      Tournaments::Rebalance.call(tournament: @t)

      assert_equal 0, @t.catch_placements.active.where(species: @walleye).count
    end

    test "shrinking ends_at deactivates placements for catches now outside the window" do
      user = create(:user, club: @club)
      entry = create(:tournament_entry, tournament: @t)
      member = create(:tournament_entry_member, tournament_entry: entry, user: user)
      member.update_column(:created_at, 2.hours.ago)
      create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)
      late = create(:catch, user: user, species: @walleye, length_inches: 22,
                            captured_at_device: 90.minutes.from_now)
      Catches::PlaceInSlots.call(catch: late)
      assert_equal late.id, @t.catch_placements.active.where(species: @walleye).first.catch_id

      @t.update!(ends_at: 1.hour.from_now)

      Tournaments::Rebalance.call(tournament: @t)

      assert_equal 0, @t.catch_placements.active.where(species: @walleye).count
    end

    test "expanding ends_at pulls in newly-eligible catches" do
      user = create(:user, club: @club)
      entry = create(:tournament_entry, tournament: @t)
      member = create(:tournament_entry_member, tournament_entry: entry, user: user)
      member.update_column(:created_at, 2.hours.ago)
      create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)
      # Tournament currently ends in 2h; create a catch 3h from now (out of window).
      future = create(:catch, user: user, species: @walleye, length_inches: 22,
                              captured_at_device: 3.hours.from_now)
      Catches::PlaceInSlots.call(catch: future)
      assert_empty future.catch_placements

      @t.update!(ends_at: 4.hours.from_now)
      Tournaments::Rebalance.call(tournament: @t)

      active = @t.catch_placements.active.where(species: @walleye)
      assert_equal 1, active.count
      assert_equal future.id, active.first.catch_id
    end

    test "reconcile reuses an existing inactive placement row rather than creating a duplicate" do
      user = create(:user, club: @club)
      entry = create(:tournament_entry, tournament: @t)
      member = create(:tournament_entry_member, tournament_entry: entry, user: user)
      member.update_column(:created_at, 2.hours.ago)
      slot = create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)
      c = create(:catch, user: user, species: @walleye, length_inches: 22,
                         captured_at_device: 30.minutes.ago)
      Catches::PlaceInSlots.call(catch: c)
      # Manually deactivate the row to simulate a prior shuffle.
      placement = entry.catch_placements.where(species: @walleye, slot_index: 0).first
      placement.update!(active: false)
      initial_count = ::CatchPlacement.where(catch_id: c.id, tournament_entry_id: entry.id,
                                             species_id: @walleye.id, slot_index: 0).count

      Tournaments::Rebalance.call(tournament: @t)

      final_count = ::CatchPlacement.where(catch_id: c.id, tournament_entry_id: entry.id,
                                           species_id: @walleye.id, slot_index: 0).count
      assert_equal initial_count, final_count, "expected the same row to be toggled, not a duplicate created"
      assert placement.reload.active?
    end

    test "skips disqualified catches when rebalancing" do
      user = create(:user, club: @club)
      entry = create(:tournament_entry, tournament: @t)
      member = create(:tournament_entry_member, tournament_entry: entry, user: user)
      member.update_column(:created_at, 2.hours.ago)
      create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)
      # A bigger catch but DQ'd; a smaller catch that's eligible.
      create(:catch, user: user, species: @walleye, length_inches: 28,
                      captured_at_device: 30.minutes.ago, status: :disqualified)
      ok = create(:catch, user: user, species: @walleye, length_inches: 18,
                           captured_at_device: 30.minutes.ago)

      Tournaments::Rebalance.call(tournament: @t)

      active = @t.catch_placements.active.where(species: @walleye)
      assert_equal 1, active.count
      assert_equal ok.id, active.first.catch_id
    end

    test "does not retroactively place a Day-2-joiner's pre-membership catch" do
      user = create(:user, club: @club)
      entry = create(:tournament_entry, tournament: @t)
      member = create(:tournament_entry_member, tournament_entry: entry, user: user)
      member.update_column(:created_at, 30.minutes.ago)
      create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)
      # Logged 1h ago, before member.created_at (30 min ago).
      create(:catch, user: user, species: @walleye, length_inches: 30,
                      captured_at_device: 1.hour.ago)
      # Logged 10 min ago, after the join.
      post = create(:catch, user: user, species: @walleye, length_inches: 18,
                             captured_at_device: 10.minutes.ago)

      Tournaments::Rebalance.call(tournament: @t)

      active = @t.catch_placements.active.where(species: @walleye)
      assert_equal 1, active.count
      assert_equal post.id, active.first.catch_id
    end

    private

    def with_broadcast_stub(callable)
      original = ::Placements::BroadcastLeaderboard.method(:call)
      ::Placements::BroadcastLeaderboard.define_singleton_method(:call) { |**kw| callable.call(**kw) }
      yield
    ensure
      ::Placements::BroadcastLeaderboard.singleton_class.remove_method(:call)
      ::Placements::BroadcastLeaderboard.define_singleton_method(:call, original)
    end
  end
end
