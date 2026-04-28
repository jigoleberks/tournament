require "test_helper"

module Placements
  class BroadcastLeaderboardTest < ActiveSupport::TestCase
    include ActionCable::TestHelper

    test "broadcasts a turbo stream replace to the tournament's channel" do
      club = create(:club)
      walleye = create(:species, club: club)
      t = create(:tournament, club: club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: t, species: walleye, slot_count: 1)
      user = create(:user, club: club)
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: user)

      catch_record = create(:catch, user: user, species: walleye, length_inches: 22)
      Catches::PlaceInSlots.call(catch: catch_record)

      assert_broadcasts("tournament:#{t.id}:leaderboard", 1) do
        BroadcastLeaderboard.call(tournament: t)
      end
    end
  end
end
