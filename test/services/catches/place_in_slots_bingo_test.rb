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
  end
end
