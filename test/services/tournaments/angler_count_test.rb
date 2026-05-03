require "test_helper"

module Tournaments
  class AnglerCountTest < ActiveSupport::TestCase
    test "returns 0 when no entries" do
      tournament = create(:tournament)
      assert_equal 0, AnglerCount.call(tournament: tournament)
    end

    test "counts solo entries" do
      club = create(:club)
      tournament = create(:tournament, club: club, mode: :solo)
      3.times do
        user = create(:user, club: club)
        entry = create(:tournament_entry, tournament: tournament)
        create(:tournament_entry_member, tournament_entry: entry, user: user)
      end
      assert_equal 3, AnglerCount.call(tournament: tournament)
    end

    test "counts distinct anglers across team entries" do
      club = create(:club)
      tournament = create(:tournament, club: club, mode: :team)

      # Team 1: 3 anglers
      team1 = create(:tournament_entry, tournament: tournament)
      3.times { create(:tournament_entry_member, tournament_entry: team1, user: create(:user, club: club)) }

      # Team 2: 2 anglers
      team2 = create(:tournament_entry, tournament: tournament)
      2.times { create(:tournament_entry_member, tournament_entry: team2, user: create(:user, club: club)) }

      assert_equal 5, AnglerCount.call(tournament: tournament)
    end
  end
end
