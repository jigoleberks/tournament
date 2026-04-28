require "test_helper"

module Placements
  class DetectNotificationsTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @t = create(:tournament, club: @club, mode: :team, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)

      # Joe and Ann share the same entry (team / boat scenario)
      @joe = create(:user, club: @club, name: "Joe")
      @ann = create(:user, club: @club, name: "Ann")
      @shared_entry = create(:tournament_entry, tournament: @t)
      create(:tournament_entry_member, tournament_entry: @shared_entry, user: @joe)
      create(:tournament_entry_member, tournament_entry: @shared_entry, user: @ann)
    end

    test "produces a 'bumped' notification to the displaced angler" do
      first = create(:catch, user: @joe, species: @walleye, length_inches: 18)
      Catches::PlaceInSlots.call(catch: first)

      bigger = create(:catch, user: @ann, species: @walleye, length_inches: 22)
      result = Catches::PlaceInSlots.call(catch: bigger)

      payloads = DetectNotifications.call(result: result)
      bumped_payload = payloads.find { |p| p[:reason] == "bumped" && p[:user] == @joe }
      assert bumped_payload, "expected a bumped notification to Joe"
      assert_match "bumped", bumped_payload[:body]
    end

    test "produces a 'took the lead' notification when first place changes" do
      # Separate entry for lead-change detection: solo tournament
      solo_t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: solo_t, species: @walleye, slot_count: 1)

      joe_solo = create(:tournament_entry, tournament: solo_t)
      create(:tournament_entry_member, tournament_entry: joe_solo, user: @joe)
      ann_solo = create(:tournament_entry, tournament: solo_t)
      create(:tournament_entry_member, tournament_entry: ann_solo, user: @ann)

      first = create(:catch, user: @joe, species: @walleye, length_inches: 18)
      Catches::PlaceInSlots.call(catch: first)

      bigger = create(:catch, user: @ann, species: @walleye, length_inches: 22)
      result = Catches::PlaceInSlots.call(catch: bigger)

      payloads = DetectNotifications.call(result: result)
      lead = payloads.find { |p| p[:reason] == "took_the_lead" && p[:user] == @ann }
      assert lead, "expected a took_the_lead notification to Ann"
    end
  end
end
