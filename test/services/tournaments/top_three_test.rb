require "test_helper"

module Tournaments
  class TopThreeTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @tournament = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: @tournament, species: @walleye, slot_count: 2)
    end

    def add_angler(name, catch_lengths)
      user = create(:user, club: @club, name: name)
      entry = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: entry, user: user)
      catch_lengths.each do |len|
        Catches::PlaceInSlots.call(catch: create(:catch, user: user, species: @walleye, length_inches: len))
      end
      entry
    end

    test "returns top 3 by total length" do
      add_angler("A", [10])
      add_angler("B", [20])
      add_angler("C", [15])
      add_angler("D", [5])

      result = TopThree.call(tournament: @tournament)
      assert_equal ["B", "C", "A"], result.map { |r| r[:entry].users.first.name }
    end

    test "excludes entries with zero catches" do
      add_angler("A", [20])
      add_angler("B", [15])
      add_angler("Skunked1", [])
      add_angler("Skunked2", [])

      result = TopThree.call(tournament: @tournament)
      assert_equal ["A", "B"], result.map { |r| r[:entry].users.first.name }
    end

    test "returns fewer than 3 if there aren't enough placers" do
      add_angler("A", [20])
      add_angler("Skunked", [])

      result = TopThree.call(tournament: @tournament)
      assert_equal 1, result.size
      assert_equal "A", result.first[:entry].users.first.name
    end

    test "tiebreaks by largest single fish then second-largest" do
      add_angler("A", [22, 22])  # total 44, biggest 22
      add_angler("B", [24, 20])  # total 44, biggest 24 → wins
      add_angler("C", [10])

      result = TopThree.call(tournament: @tournament)
      assert_equal ["B", "A", "C"], result.map { |r| r[:entry].users.first.name }
    end
  end
end
