require "test_helper"

module Leaderboards
  class BroadcastRevealTest < ActiveSupport::TestCase
    include ActionCable::TestHelper

    test "broadcasts a turbo stream replace to the tournament's reveal channel" do
      club = create(:club)
      walleye = create(:species, club: club)
      t = create(:tournament, club: club, starts_at: 2.hours.ago, ends_at: 1.hour.ago,
                 blind_leaderboard: true)
      create(:scoring_slot, tournament: t, species: walleye, slot_count: 1)
      create(:tournament_entry, tournament: t)

      assert_broadcasts("tournament:#{t.id}:leaderboard:reveal", 1) do
        BroadcastReveal.call(tournament: t)
      end
    end
  end
end
