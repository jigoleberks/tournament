require "test_helper"

module Catches
  class PlaceInSlotsBingoTest < ActiveSupport::TestCase
    test "a bingo catch creates no placements but flags the tournament affected" do
      club = Club.create!(name: "C")
      walleye, = create_bingo_species!
      t = Tournament.new(club: club, name: "B", mode: :solo, format: :bingo,
                         starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
      t.save!
      u = User.create!(name: "A", email: "a@example.com")
      e = t.tournament_entries.create!
      e.tournament_entry_members.create!(user: u)

      c = create(:catch, user: u, species: walleye, length_inches: 15, captured_at_device: 1.hour.ago)

      result = Catches::PlaceInSlots.call(catch: c, broadcast: false)

      assert_equal 0, CatchPlacement.where(catch_id: c.id).count
      assert_includes result[:affected_tournaments].map(&:id), t.id
    end

    test "a geofence-excluded bingo catch does not flag the tournament affected" do
      club = Club.create!(name: "C")
      walleye, = create_bingo_species!
      t = Tournament.new(club: club, name: "B", mode: :solo, format: :bingo,
                         starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
      t.save!
      u = User.create!(name: "A", email: "geo@example.com")
      e = t.tournament_entries.create!
      e.tournament_entry_members.create!(user: u)

      # (0, 0) is far outside Saskatchewan — EvaluateCard drops it, so the card
      # can't have changed and no rebroadcast should be queued.
      c = create(:catch, user: u, species: walleye, length_inches: 15,
                 captured_at_device: 1.hour.ago, latitude: 0.0, longitude: 0.0)

      result = Catches::PlaceInSlots.call(catch: c, broadcast: false)

      refute_includes result[:affected_tournaments].map(&:id), t.id
    end

    test "a lead-taking bingo catch loads the entry's catches once, not again for the before-state" do
      club = Club.create!(name: "C")
      walleye, = create_bingo_species!
      t = Tournament.new(club: club, name: "B", mode: :solo, format: :bingo,
                         starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
      t.save!
      alice = User.create!(name: "Alice", email: "alice@example.com")
      ea = t.tournament_entries.create!
      ea.tournament_entry_members.create!(user: alice)
      # A second, empty-carded entry so Build's all-entries member pluck differs
      # from the leader-only before-state pluck — otherwise identical SQL and the
      # redundant second query is masked by ActiveRecord's query cache.
      bob = User.create!(name: "Bob", email: "bob@example.com")
      eb = t.tournament_entries.create!
      eb.tournament_entry_members.create!(user: bob)

      c = create(:catch, user: alice, species: walleye, length_inches: 16,
                 captured_at_device: 1.hour.ago, status: :synced)

      # The leaderboard build already loads and evaluates every entry's catches
      # (one EvaluateCard.catches_by_entry, which plucks the entries' members).
      # The before-state (leader's card minus this catch) must reuse that load
      # rather than running catches_by_entry a second time — so exactly one
      # member pluck, not two.
      queries = count_queries(/FROM .?tournament_entry_members.? WHERE/i) do
        Catches::PlaceInSlots.call(catch: c)
      end
      assert_equal 1, queries,
        "the before-card must reuse the leaderboard's already-loaded catches"
    end

    # A duplicate concurrent POST of one client_uuid (recover "Re-submit"
    # racing a background drain, or two open tabs) reaches RunPlacementPipeline
    # a second time while placements_evaluated_at is still NULL — @catch.lock!
    # only serializes the second run behind the first, it doesn't cancel it.
    # For slot formats already_placed_ids makes that pass a no-op, but bingo
    # keeps no CatchPlacement rows at all, so the second run re-broadcast every
    # entrant's card and re-fired the took-the-lead push for a single fish.
    test "a repeated first-placement run on a bingo catch is a no-op" do
      club = Club.create!(name: "C")
      walleye, = create_bingo_species!
      t = Tournament.new(club: club, name: "B", mode: :solo, format: :bingo,
                         starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
      t.save!
      u = User.create!(name: "A", email: "dup@example.com")
      e = t.tournament_entries.create!
      e.tournament_entry_members.create!(user: u)

      c = create(:catch, user: u, species: walleye, length_inches: 15,
                 captured_at_device: 1.hour.ago, status: :synced)

      broadcasts = with_broadcast_spy do |calls|
        first = Catches::PlaceInSlots.call(catch: c)
        assert_includes first[:affected_tournaments].map(&:id), t.id,
          "precondition: the first run must broadcast the card"

        second = Catches::PlaceInSlots.call(catch: c)
        assert_empty second[:affected_tournaments],
          "the duplicate run re-broadcast the card and would re-push the lead"
        calls
      end
      assert_equal [t.id], broadcasts, "the card must be broadcast exactly once for one fish"
    end

    # The guard above must not swallow the API's crash-recovery re-run either.
    # PlaceInSlots stamps placed_at inside its transaction but broadcasts after
    # the commit, so a crash in that gap (the Solid Queue enqueue is the
    # documented deadlock point) leaves a placed catch that was never announced.
    # Api::CatchesController#serialize_existing re-runs the pipeline for exactly
    # that case; guarding on placed_at alone skipped it, and every entrant's
    # card stayed a square stale for the rest of the night.
    test "a bingo catch placed before the in-flight window still rebroadcasts" do
      club = Club.create!(name: "C")
      walleye, = create_bingo_species!
      t = Tournament.new(club: club, name: "B", mode: :solo, format: :bingo,
                         starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
      t.save!
      u = User.create!(name: "A", email: "crash-retry@example.com")
      e = t.tournament_entries.create!
      e.tournament_entry_members.create!(user: u)

      c = create(:catch, user: u, species: walleye, length_inches: 15,
                 captured_at_device: 1.hour.ago, status: :synced)

      # The crashed run: placements committed (placed_at stamped), but the
      # post-commit broadcast never happened, so placements_evaluated_at is nil.
      # A literal age, not one derived from IN_FLIGHT_WINDOW — deriving it would
      # move with the constant and the test could never fail.
      assert_operator Catches::PlaceInSlots::IN_FLIGHT_WINDOW, :<, 10.minutes,
        "this test assumes 10 minutes is outside the in-flight window"
      c.update_columns(placed_at: 10.minutes.ago, placements_evaluated_at: nil)

      result = Catches::PlaceInSlots.call(catch: c)

      assert_includes result[:affected_tournaments].map(&:id), t.id,
        "the crash-recovery re-run must rebroadcast the card the dead run never announced"
    end

    # The guard above must not reach the judge flows: ApplyJudgeAction
    # deliberately re-places a catch it has just deactivated/reinstated, and
    # passes broadcast: false to do its own broadcast afterwards. A bingo card
    # still has to be rebuilt for those.
    test "a judge re-place still flags a bingo tournament after the first run" do
      club = Club.create!(name: "C")
      walleye, = create_bingo_species!
      t = Tournament.new(club: club, name: "B", mode: :solo, format: :bingo,
                         starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
      t.save!
      u = User.create!(name: "A", email: "judge-replace@example.com")
      e = t.tournament_entries.create!
      e.tournament_entry_members.create!(user: u)

      c = create(:catch, user: u, species: walleye, length_inches: 15,
                 captured_at_device: 1.hour.ago, status: :synced)

      Catches::PlaceInSlots.call(catch: c)
      result = Catches::PlaceInSlots.call(catch: c, broadcast: false)

      assert_includes result[:affected_tournaments].map(&:id), t.id,
        "a judge re-place must still rebuild the card"
    end
  end
end
