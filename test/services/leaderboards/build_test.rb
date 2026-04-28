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
  end
end
