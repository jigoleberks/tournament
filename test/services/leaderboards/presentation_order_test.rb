require "test_helper"

module Leaderboards
  class PresentationOrderTest < ActiveSupport::TestCase
    Entry = Struct.new(:id, :display_name)
    Scope = Leaderboards::ViewerScope::Scope

    def row(id, name)
      { entry: Entry.new(id, name), total: 0 }
    end

    test "full visibility preserves input rank order even when alpha differs" do
      scope = Scope.new(visibility: :full, entry_id: nil)
      rows = [row(1, "Zebra"), row(2, "Alpha"), row(3, "Mike")]

      result = PresentationOrder.call(rows: rows, viewer_scope: scope)

      assert_equal [1, 2, 3], result.map { |r| r[:entry].id }
    end

    test "own_entry_only puts viewer entry first then others alphabetical" do
      scope = Scope.new(visibility: :own_entry_only, entry_id: 7)
      rows = [
        row(2, "Bravo"),
        row(7, "Zulu"),    # viewer's entry
        row(5, "alpha"),   # lowercase to verify case-insensitive sort
        row(9, "Charlie")
      ]

      result = PresentationOrder.call(rows: rows, viewer_scope: scope)

      assert_equal [7, 5, 2, 9], result.map { |r| r[:entry].id },
        "viewer entry first, then case-insensitive alphabetical: alpha, Bravo, Charlie"
    end

    test "own_entry_only with entry_id not in rows treats all as alphabetical" do
      scope = Scope.new(visibility: :own_entry_only, entry_id: 999)
      rows = [row(2, "Bravo"), row(5, "alpha"), row(9, "Charlie")]

      result = PresentationOrder.call(rows: rows, viewer_scope: scope)

      assert_equal [5, 2, 9], result.map { |r| r[:entry].id }
    end

    test "entries_only sorts everything alphabetical regardless of input order" do
      scope = Scope.new(visibility: :entries_only, entry_id: nil)
      rows = [row(2, "Bravo"), row(7, "Zulu"), row(5, "alpha"), row(9, "Charlie")]

      result = PresentationOrder.call(rows: rows, viewer_scope: scope)

      assert_equal [5, 2, 9, 7], result.map { |r| r[:entry].id }
    end

    test "alphabetical tiebreaker uses entry id ascending for identical names" do
      scope = Scope.new(visibility: :entries_only, entry_id: nil)
      rows = [row(8, "Same"), row(3, "Same"), row(11, "Same")]

      result = PresentationOrder.call(rows: rows, viewer_scope: scope)

      assert_equal [3, 8, 11], result.map { |r| r[:entry].id }
    end
  end
end
