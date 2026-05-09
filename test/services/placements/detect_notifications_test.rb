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

    test "suppresses bumped notification when the affected tournament is blind+active" do
      @t.update_columns(blind_leaderboard: true)

      first = create(:catch, user: @joe, species: @walleye, length_inches: 18)
      Catches::PlaceInSlots.call(catch: first)

      bigger = create(:catch, user: @ann, species: @walleye, length_inches: 22)
      result = Catches::PlaceInSlots.call(catch: bigger)

      payloads = DetectNotifications.call(result: result)
      assert_empty payloads, "expected no notifications during a blind+active tournament"
    end

    test "does not suppress pushes for non-blind tournaments when user is also in a blind one" do
      blind_t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                       blind_leaderboard: true, mode: :solo)
      create(:scoring_slot, tournament: blind_t, species: @walleye, slot_count: 1)
      joe_blind = create(:tournament_entry, tournament: blind_t)
      create(:tournament_entry_member, tournament_entry: joe_blind, user: @joe)
      ann_blind = create(:tournament_entry, tournament: blind_t)
      create(:tournament_entry_member, tournament_entry: ann_blind, user: @ann)

      open_t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now, mode: :solo)
      create(:scoring_slot, tournament: open_t, species: @walleye, slot_count: 1)
      joe_open = create(:tournament_entry, tournament: open_t)
      create(:tournament_entry_member, tournament_entry: joe_open, user: @joe)
      ann_open = create(:tournament_entry, tournament: open_t)
      create(:tournament_entry_member, tournament_entry: ann_open, user: @ann)

      first = create(:catch, user: @joe, species: @walleye, length_inches: 18)
      Catches::PlaceInSlots.call(catch: first)

      bigger = create(:catch, user: @ann, species: @walleye, length_inches: 22)
      result = Catches::PlaceInSlots.call(catch: bigger)

      payloads = DetectNotifications.call(result: result)
      tournaments = payloads.map { |p| p[:tournament] }
      assert_includes tournaments, open_t,    "expected payloads for the non-blind tournament"
      assert_not_includes tournaments, blind_t, "expected no payloads for the blind tournament"
    end

    test "skips lead-change notifications for Hidden Length tournaments while target is unrevealed" do
      club = create(:club)
      walleye = create(:species, club: club)
      user = create(:user, club: club)
      t = build(:tournament, club: club, format: :hidden_length, mode: :solo,
                kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      t.scoring_slots.build(species: walleye, slot_count: 1)
      t.save!
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: user)

      caught = create(:catch, user: user, species: walleye, length_inches: 22,
                      captured_at_device: 30.minutes.ago)
      placement = CatchPlacement.create!(catch: caught, tournament: t,
                                         tournament_entry: entry, species: walleye,
                                         slot_index: 0, active: true)

      result = { created: [placement], bumped: [], affected_tournaments: [t] }
      payloads = DetectNotifications.call(result: result)
      assert_empty payloads.select { |p| p[:reason] == "took_the_lead" },
                   "Hidden Length pre-reveal should not push 'took the lead'"
    end

    test "still emits lead-change notifications after Hidden Length target is rolled" do
      club = create(:club)
      walleye = create(:species, club: club)
      user = create(:user, club: club)
      t = build(:tournament, club: club, format: :hidden_length, mode: :solo,
                kind: :event, starts_at: 2.hours.ago, ends_at: 1.minute.ago)
      t.scoring_slots.build(species: walleye, slot_count: 1)
      t.save!
      t.update!(hidden_length_target: BigDecimal("17.00"))
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: user)

      caught = create(:catch, user: user, species: walleye, length_inches: 17,
                      captured_at_device: 30.minutes.ago)
      placement = CatchPlacement.create!(catch: caught, tournament: t,
                                         tournament_entry: entry, species: walleye,
                                         slot_index: 0, active: true)

      result = { created: [placement], bumped: [], affected_tournaments: [t] }
      payloads = DetectNotifications.call(result: result)
      assert payloads.any? { |p| p[:reason] == "took_the_lead" && p[:user] == user },
             "post-reveal lead changes should still notify"
    end
  end
end
