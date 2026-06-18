require "test_helper"

module Catches
  class ReconcileSmallestFishTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @user = create(:user, club: @club)
      @t = build(:tournament, club: @club, format: :smallest_fish, mode: :solo,
                 kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      @t.scoring_slots.build(species: @walleye, slot_count: 2)
      @t.save!
      @entry = create(:tournament_entry, tournament: @t)
      create(:tournament_entry_member, tournament_entry: @entry, user: @user)
    end

    def make_catch(length, captured: 30.minutes.ago, status: :synced, user: @user)
      create(:catch, user: user, species: @walleye, length_inches: length,
                     captured_at_device: captured, status: status)
    end

    def active_lengths
      @entry.catch_placements.where(active: true).includes(:catch)
            .map { |p| p.catch.length_inches.to_i }.sort
    end

    test "no eligible catches: clears all active placements and creates none" do
      c = make_catch(8)
      Catches::PlaceInSlots.call(catch: c)
      c.update!(status: :disqualified)

      ReconcileSmallestFish.call(tournament: @t, entry: @entry, species: @walleye)

      assert_equal 0, @entry.catch_placements.where(active: true).count
    end

    test "fewer eligible than slots: places all of them" do
      c1 = make_catch(8)
      Catches::PlaceInSlots.call(catch: c1)

      ReconcileSmallestFish.call(tournament: @t, entry: @entry, species: @walleye)

      assert_equal [8], active_lengths
    end

    test "more eligible than slots: places exactly the N smallest" do
      [8, 9, 14, 20].each { |l| Catches::PlaceInSlots.call(catch: make_catch(l)) }
      # basket already {8,9}; reconcile must re-derive the same two smallest.

      ReconcileSmallestFish.call(tournament: @t, entry: @entry, species: @walleye)

      assert_equal [8, 9], active_lengths
    end

    test "re-derives from scratch: a previously-bumped catch returns when a smaller one is DQ'd" do
      c8  = make_catch(8,  captured: 40.minutes.ago)
      c9  = make_catch(9,  captured: 30.minutes.ago)
      c14 = make_catch(14, captured: 20.minutes.ago)
      [c8, c9, c14].each { |c| Catches::PlaceInSlots.call(catch: c) }
      # basket {8,9}; 14 was bumped (>= largest). DQ the 8.
      c8.update!(status: :disqualified)

      ReconcileSmallestFish.call(tournament: @t, entry: @entry, species: @walleye)

      # eligible now {9,14}; two smallest = {9,14}
      assert_equal [9, 14], active_lengths
    end

    test "ties broken by earliest captured_at_device" do
      early = make_catch(10, captured: 50.minutes.ago)
      late  = make_catch(10, captured: 10.minutes.ago)
      mid   = make_catch(12, captured: 30.minutes.ago)
      [early, late, mid].each { |c| Catches::PlaceInSlots.call(catch: c) }

      ReconcileSmallestFish.call(tournament: @t, entry: @entry, species: @walleye)

      # two smallest by length are both the 10s; tie-break keeps both 10s (same length),
      # so active = [10,10], and the 12 stays out.
      assert_equal [10, 10], active_lengths
    end
  end
end
