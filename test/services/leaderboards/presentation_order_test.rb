require "test_helper"

module Leaderboards
  class PresentationOrderTest < ActiveSupport::TestCase
    Scope = Leaderboards::ViewerScope::Scope

    # Use real TournamentEntry records (build_stubbed — no DB write) so that
    # PresentationOrder is exercised against the actual `display_name` contract.
    # Renaming or removing TournamentEntry#display_name will fail this suite.
    def row(entry)
      { entry: entry, total: 0 }
    end

    def entry(name)
      build_stubbed(:tournament_entry, name: name)
    end

    test "full visibility preserves input rank order even when alpha differs" do
      e1, e2, e3 = entry("Zebra"), entry("Alpha"), entry("Mike")
      scope = Scope.new(visibility: :full, entry_id: nil)

      result = PresentationOrder.call(rows: [row(e1), row(e2), row(e3)], viewer_scope: scope)

      assert_equal [e1.id, e2.id, e3.id], result.map { |r| r[:entry].id }
    end

    test "own_entry_only puts viewer entry first then others alphabetical" do
      bravo   = entry("Bravo")
      viewer  = entry("Zulu")
      alpha   = entry("alpha")     # lowercase to verify case-insensitive sort
      charlie = entry("Charlie")
      scope = Scope.new(visibility: :own_entry_only, entry_id: viewer.id)

      result = PresentationOrder.call(
        rows: [row(bravo), row(viewer), row(alpha), row(charlie)],
        viewer_scope: scope
      )

      assert_equal [viewer.id, alpha.id, bravo.id, charlie.id],
        result.map { |r| r[:entry].id },
        "viewer entry first, then case-insensitive alphabetical: alpha, Bravo, Charlie"
    end

    test "own_entry_only with entry_id not in rows treats all as alphabetical" do
      bravo, alpha, charlie = entry("Bravo"), entry("alpha"), entry("Charlie")
      scope = Scope.new(visibility: :own_entry_only, entry_id: 0)

      result = PresentationOrder.call(rows: [row(bravo), row(alpha), row(charlie)], viewer_scope: scope)

      assert_equal [alpha.id, bravo.id, charlie.id], result.map { |r| r[:entry].id }
    end

    test "entries_only sorts everything alphabetical regardless of input order" do
      bravo, zulu, alpha, charlie = entry("Bravo"), entry("Zulu"), entry("alpha"), entry("Charlie")
      scope = Scope.new(visibility: :entries_only, entry_id: nil)

      result = PresentationOrder.call(
        rows: [row(bravo), row(zulu), row(alpha), row(charlie)],
        viewer_scope: scope
      )

      assert_equal [alpha.id, bravo.id, charlie.id, zulu.id], result.map { |r| r[:entry].id }
    end

    test "alphabetical tiebreaker uses entry id ascending for identical names" do
      # build_stubbed assigns ids in creation order, so create out of order then
      # sort by id to recover the expected ascending sequence.
      e_b = entry("Same")
      e_a = entry("Same")
      e_c = entry("Same")
      ascending_ids = [e_a.id, e_b.id, e_c.id].sort
      scope = Scope.new(visibility: :entries_only, entry_id: nil)

      result = PresentationOrder.call(rows: [row(e_b), row(e_a), row(e_c)], viewer_scope: scope)

      assert_equal ascending_ids, result.map { |r| r[:entry].id }
    end

    test "uses TournamentEntry#display_name (falls back to member names when name is blank)" do
      # Anchor the contract: PresentationOrder reads display_name, not just name.
      # If display_name is renamed/removed, this test fails.
      club = create(:club)
      tournament = create(:tournament, club: club, mode: :team)
      alice = create(:user, club: club, name: "Alice")
      bob   = create(:user, club: club, name: "Bob")
      named = create(:tournament_entry, tournament: tournament, name: "Charlie Boat")
      unnamed = create(:tournament_entry, tournament: tournament, name: nil)
      create(:tournament_entry_member, tournament_entry: unnamed, user: alice)
      create(:tournament_entry_member, tournament_entry: unnamed, user: bob)

      scope = Scope.new(visibility: :entries_only, entry_id: nil)
      result = PresentationOrder.call(rows: [row(named), row(unnamed)], viewer_scope: scope)

      # "Alice + Bob" (display_name fallback) sorts before "Charlie Boat".
      assert_equal [unnamed.id, named.id], result.map { |r| r[:entry].id }
    end
  end
end
