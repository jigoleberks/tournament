require "test_helper"

module Leaderboards
  class BuildTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @tournament = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: @tournament, species: @walleye, slot_count: 2)
    end

    test "ranks entries by sum of active placement lengths, desc" do
      a = create(:user, club: @club, name: "A")
      b = create(:user, club: @club, name: "B")
      [a, b].each do |u|
        e = create(:tournament_entry, tournament: @tournament)
        create(:tournament_entry_member, tournament_entry: e, user: u)
      end

      ca1 = create(:catch, user: a, species: @walleye, length_inches: 20)
      ca2 = create(:catch, user: a, species: @walleye, length_inches: 17)
      cb1 = create(:catch, user: b, species: @walleye, length_inches: 22)
      [ca1, ca2, cb1].each { |c| Catches::PlaceInSlots.call(catch: c) }

      result = Build.call(tournament: @tournament)
      assert_equal ["A", "B"], result.map { |row| row[:entry].users.first.name }
      assert_equal [37, 22], result.map { |row| row[:total].to_i }
    end

    test "fish exposes approver_name when last judge action is an approve" do
      a = create(:user, club: @club, name: "A")
      e = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: e, user: a)
      judge = create(:user, club: @club, name: "Judge Judy")

      approved = create(:catch, user: a, species: @walleye, length_inches: 22)
      Catches::PlaceInSlots.call(catch: approved)
      create(:judge_action, judge_user: judge, catch: approved, action: :approve)

      unreviewed = create(:catch, user: a, species: @walleye, length_inches: 18)
      Catches::PlaceInSlots.call(catch: unreviewed)

      row = Build.call(tournament: @tournament).first
      by_id = row[:fish].index_by { |f| f[:id] }
      assert_equal "Judge Judy", by_id[approved.id][:approver_name]
      assert_nil by_id[unreviewed.id][:approver_name]
    end

    test "fish list per entry is ordered largest to smallest" do
      a = create(:user, club: @club, name: "A")
      e = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: e, user: a)

      # Insert in ascending order so the natural placement-id order is ascending too;
      # only an explicit length sort can yield [22, 18].
      [15, 18, 22].each do |len|
        Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: @walleye, length_inches: len))
      end

      row = Build.call(tournament: @tournament).first
      assert_equal [22, 18], row[:fish].map { |f| f[:length_inches].to_i },
                   "expected per-entry fish list to be ordered largest to smallest"
    end

    test "breaks total-length ties by largest single fish" do
      a = create(:user, club: @club, name: "A")
      b = create(:user, club: @club, name: "B")
      ea = create(:tournament_entry, tournament: @tournament)
      eb = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: ea, user: a)
      create(:tournament_entry_member, tournament_entry: eb, user: b)

      # A: 22 + 22 = 44, biggest fish 22
      # B: 24 + 20 = 44, biggest fish 24 → B wins tiebreaker
      [22, 22].each { |len| Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: @walleye, length_inches: len)) }
      [24, 20].each { |len| Catches::PlaceInSlots.call(catch: create(:catch, user: b, species: @walleye, length_inches: len)) }

      result = Build.call(tournament: @tournament)
      assert_equal ["B", "A"], result.map { |row| row[:entry].users.first.name }
    end

    test "breaks identical-fish ties by earliest captured_at_device" do
      a = create(:user, club: @club, name: "A")
      b = create(:user, club: @club, name: "B")
      ea = create(:tournament_entry, tournament: @tournament)
      eb = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: ea, user: a)
      create(:tournament_entry_member, tournament_entry: eb, user: b)

      earlier = create(:catch, user: a, species: @walleye, length_inches: 22, captured_at_device: 30.minutes.ago)
      later   = create(:catch, user: b, species: @walleye, length_inches: 22, captured_at_device: 10.minutes.ago)
      [earlier, later].each { |c| Catches::PlaceInSlots.call(catch: c) }

      result = Build.call(tournament: @tournament)
      assert_equal ["A", "B"], result.map { |row| row[:entry].users.first.name }
    end

    test "row exposes earliest_catch_at" do
      a = create(:user, club: @club, name: "A")
      ea = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: ea, user: a)
      early = create(:catch, user: a, species: @walleye, length_inches: 18, captured_at_device: 1.hour.ago)
      late  = create(:catch, user: a, species: @walleye, length_inches: 19, captured_at_device: 30.minutes.ago)
      [early, late].each { |c| Catches::PlaceInSlots.call(catch: c) }

      result = Build.call(tournament: @tournament)
      assert_in_delta early.captured_at_device, result.first[:earliest_catch_at], 1.second
    end
  end
end
