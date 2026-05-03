require "test_helper"

module Tournaments
  class SeasonPointsAwardedTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
    end

    # Helper: builds a finished, points-eligible tournament with N solo anglers.
    # `lengths_by_index` maps angler index → array of catch lengths.
    # Returns [tournament, anglers].
    def build_finished_solo(n_anglers, lengths_by_index = {})
      tournament = create(
        :tournament,
        club: @club,
        mode: :solo,
        awards_season_points: true,
        starts_at: 2.days.ago,
        ends_at:   1.day.ago
      )
      create(:scoring_slot, tournament: tournament, species: @walleye, slot_count: 2)
      anglers = n_anglers.times.map do |i|
        u = create(:user, club: @club)
        e = create(:tournament_entry, tournament: tournament)
        create(:tournament_entry_member, tournament_entry: e, user: u)
        Array(lengths_by_index[i]).each do |len|
          Catches::PlaceInSlots.call(catch: create(:catch, user: u, species: @walleye, length_inches: len, captured_at_device: 1.5.days.ago))
        end
        u
      end
      [tournament, anglers]
    end

    test "returns {} when not points-eligible" do
      tournament = create(:tournament, club: @club, awards_season_points: false, ends_at: 1.hour.ago)
      assert_equal({}, SeasonPointsAwarded.call(tournament: tournament))
    end

    test "returns {} when tournament has not ended" do
      tournament = create(:tournament, club: @club, awards_season_points: true, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      assert_equal({}, SeasonPointsAwarded.call(tournament: tournament))
    end

    test "returns {} when ends_at is nil" do
      tournament = create(:tournament, club: @club, awards_season_points: true, starts_at: 1.hour.ago, ends_at: nil)
      assert_equal({}, SeasonPointsAwarded.call(tournament: tournament))
    end

    test "returns {} when fewer than 3 anglers" do
      tournament, _ = build_finished_solo(2, { 0 => [20], 1 => [15] })
      assert_equal({}, SeasonPointsAwarded.call(tournament: tournament))
    end

    test "awards [3,2,1] for 3 anglers in solo mode" do
      tournament, anglers = build_finished_solo(3, { 0 => [20], 1 => [15], 2 => [10] })
      result = SeasonPointsAwarded.call(tournament: tournament)
      assert_equal({ anglers[0].id => 3, anglers[1].id => 2, anglers[2].id => 1 }, result)
    end

    test "awards [6,4,2] for 10 anglers" do
      lengths = (0...10).each_with_object({}) { |i, h| h[i] = [20 - i] }
      tournament, anglers = build_finished_solo(10, lengths)
      result = SeasonPointsAwarded.call(tournament: tournament)
      assert_equal 6, result[anglers[0].id]
      assert_equal 4, result[anglers[1].id]
      assert_equal 2, result[anglers[2].id]
      (3..9).each { |i| assert_nil result[anglers[i].id] }
    end

    test "awards [9,6,3] for 20 anglers" do
      lengths = (0...20).each_with_object({}) { |i, h| h[i] = [25 - i] }
      tournament, anglers = build_finished_solo(20, lengths)
      result = SeasonPointsAwarded.call(tournament: tournament)
      assert_equal 9, result[anglers[0].id]
      assert_equal 6, result[anglers[1].id]
      assert_equal 3, result[anglers[2].id]
    end

    test "awards 1st and 2nd only when fewer than 3 entries have catches" do
      tournament, anglers = build_finished_solo(5, { 0 => [20], 1 => [15] })  # angler 2,3,4 skunked
      result = SeasonPointsAwarded.call(tournament: tournament)
      assert_equal 3, result[anglers[0].id]
      assert_equal 2, result[anglers[1].id]
      assert_nil result[anglers[2].id]
      assert_nil result[anglers[3].id]
      assert_nil result[anglers[4].id]
    end

    test "team mode: every member of a placing entry gets the points" do
      tournament = create(
        :tournament,
        club: @club,
        mode: :team,
        awards_season_points: true,
        starts_at: 2.days.ago,
        ends_at: 1.day.ago
      )
      create(:scoring_slot, tournament: tournament, species: @walleye, slot_count: 2)

      # Team 1 (3 anglers): biggest fish → wins (25")
      team1_users = 3.times.map { create(:user, club: @club) }
      team1 = create(:tournament_entry, tournament: tournament)
      team1_users.each { |u| create(:tournament_entry_member, tournament_entry: team1, user: u) }
      Catches::PlaceInSlots.call(catch: create(:catch, user: team1_users.first, species: @walleye, length_inches: 25, captured_at_device: 1.5.days.ago))

      # Team 2 (2 anglers): second (18")
      team2_users = 2.times.map { create(:user, club: @club) }
      team2 = create(:tournament_entry, tournament: tournament)
      team2_users.each { |u| create(:tournament_entry_member, tournament_entry: team2, user: u) }
      Catches::PlaceInSlots.call(catch: create(:catch, user: team2_users.first, species: @walleye, length_inches: 18, captured_at_device: 1.5.days.ago))

      # Team 3 (3 anglers): third (12")
      team3_users = 3.times.map { create(:user, club: @club) }
      team3 = create(:tournament_entry, tournament: tournament)
      team3_users.each { |u| create(:tournament_entry_member, tournament_entry: team3, user: u) }
      Catches::PlaceInSlots.call(catch: create(:catch, user: team3_users.first, species: @walleye, length_inches: 12, captured_at_device: 1.5.days.ago))

      # 8 anglers total → [3,2,1] scale
      result = SeasonPointsAwarded.call(tournament: tournament)
      team1_users.each { |u| assert_equal 3, result[u.id], "team1 member #{u.id} should get 3" }
      team2_users.each { |u| assert_equal 2, result[u.id], "team2 member #{u.id} should get 2" }
      team3_users.each { |u| assert_equal 1, result[u.id], "team3 member #{u.id} should get 1" }
    end
  end
end
