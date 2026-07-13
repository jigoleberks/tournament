require "test_helper"

module Tournaments
  class WinnersForTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @species = create(:species, club: @club)
    end

    def build_tournament(name)
      t = create(:tournament, club: @club, name: name,
                 starts_at: 2.days.ago, ends_at: 1.day.ago)
      create(:scoring_slot, tournament: t, species: @species, slot_count: 2)
      t
    end

    def add_angler(tournament, name, lengths)
      user = create(:user, club: @club, name: name)
      entry = create(:tournament_entry, tournament: tournament)
      create(:tournament_entry_member, tournament_entry: entry, user: user)
      lengths.each_with_index do |len, i|
        c = create(:catch, user: user, species: @species, length_inches: len,
                           captured_at_device: tournament.ends_at - 1.hour)
        create(:catch_placement, catch: c, tournament: tournament,
                                  tournament_entry: entry, species: @species, slot_index: i)
      end
      entry
    end

    test "returns the top entry per tournament keyed by tournament id" do
      t1 = build_tournament("T1")
      t2 = build_tournament("T2")
      add_angler(t1, "A", [10, 5])
      winner1 = add_angler(t1, "B", [20, 18])
      winner2 = add_angler(t2, "C", [30])

      result = WinnersFor.call(tournaments: [t1, t2])

      assert_equal winner1.id, result[t1.id].id
      assert_equal winner2.id, result[t2.id].id
    end

    test "winner value is nil for tournaments with no placed catches" do
      t = build_tournament("Empty")

      result = WinnersFor.call(tournaments: [t])

      assert_nil result[t.id]
      assert_includes result.keys, t.id
    end

    test "returns an empty hash for an empty tournament list" do
      assert_equal({}, WinnersFor.call(tournaments: []))
    end

    test "bingo tournament: returns the entry with squares beyond the free cell, not a crash" do
      walleye, = create_bingo_species!
      t = create(:tournament, club: @club, name: "Bingo", format: :bingo, mode: :solo,
                 starts_at: 2.days.ago, ends_at: 1.day.ago)

      catcher_user = create(:user, club: @club, name: "Catcher")
      catcher_entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: catcher_entry, user: catcher_user)
      create(:catch, user: catcher_user, species: walleye, length_inches: 15,
                     captured_at_device: t.ends_at - 1.hour)

      empty_user = create(:user, club: @club, name: "Empty")
      empty_entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: empty_entry, user: empty_user)

      result = WinnersFor.call(tournaments: [t])

      assert_equal catcher_entry.id, result[t.id].id
    end

    test "bingo tournament: nil winner when the only entry has just the free square" do
      create_bingo_species!
      t = create(:tournament, club: @club, name: "Bingo Empty", format: :bingo, mode: :solo,
                 starts_at: 2.days.ago, ends_at: 1.day.ago)
      user = create(:user, club: @club, name: "NoCatches")
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: user)

      result = WinnersFor.call(tournaments: [t])

      assert_nil result[t.id]
    end

    test "issues a bounded number of queries regardless of tournament count" do
      tournaments = 5.times.map { |i| build_tournament("T#{i}") }
      tournaments.each_with_index { |t, i| add_angler(t, "angler#{i}", [10 + i]) }

      queries = []
      callback = ->(*, payload) {
        sql = payload[:sql]
        next if payload[:name] == "SCHEMA"
        next if sql =~ /\A(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/
        queries << sql
      }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        WinnersFor.call(tournaments: tournaments)
      end

      assert_operator queries.size, :<=, 10,
        "expected WinnersFor to batch its queries; got #{queries.size}:\n#{queries.join("\n")}"
    end
  end
end
