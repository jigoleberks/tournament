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

    test "tagged tournament reveal renders the tagged leaderboard partial" do
      club = create(:club)
      tagged = Species.find_or_create_by!(name: "Tagged Walleye")
      t = build(:tournament, club: club, format: :tagged, mode: :solo,
                starts_at: 2.hours.ago, ends_at: 1.hour.ago, blind_leaderboard: true)
      t.scoring_slots.build(species: tagged, slot_count: 1)
      t.save!
      create(:tournament_entry, tournament: t)

      BroadcastReveal.call(tournament: t)

      payload = broadcasts("tournament:#{t.id}:leaderboard:reveal").last
      html = payload.is_a?(String) ? payload : payload.to_s
      assert_includes html, "Tickets",
                       "reveal should render the tagged partial (Tickets column), not the standard leaderboard"
    end
  end
end
