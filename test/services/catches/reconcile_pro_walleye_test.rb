require "test_helper"

module Catches
  class ReconcileProWalleyeTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, name: "Walleye")
      @user = create(:user, club: @club)
      @t = build(:tournament, club: @club, format: :pro_walleye, mode: :team,
                 starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      @t.scoring_slots.build(species: @walleye, slot_count: 5)
      @t.save!
      @entry = create(:tournament_entry, tournament: @t)
      create(:tournament_entry_member, tournament_entry: @entry, user: @user)
    end

    def make(len, captured: 30.minutes.ago, status: :synced)
      create(:catch, user: @user, species: @walleye, length_inches: len,
                     captured_at_device: captured, status: status)
    end

    def active_lengths
      @entry.catch_placements.where(active: true).includes(:catch)
            .map { |p| p.catch.length_inches.to_i }.sort
    end

    test "with no overs, keeps up to the 5 largest unders" do
      [10, 12, 14, 16, 18, 20].each { |l| PlaceInSlots.call(catch: make(l)) } # 6 unders
      ReconcileProWalleye.call(tournament: @t, entry: @entry, species: @walleye)
      assert_equal [12, 14, 16, 18, 20], active_lengths
    end

    test "keeps the 2 largest overs and fills the rest with the largest unders" do
      # 3 overs (cap 2) + 4 unders (only 3 slots left) — drops the smallest of each.
      [16, 17, 18, 19, 24, 26, 28].each { |l| PlaceInSlots.call(catch: make(l)) }
      ReconcileProWalleye.call(tournament: @t, entry: @entry, species: @walleye)
      assert_equal [17, 18, 19, 26, 28], active_lengths
    end

    test "a DQ'd over frees the over slot for the next-largest over" do
      placed = [24, 26, 28].map { |l| c = make(l); PlaceInSlots.call(catch: c); c }
      # Over cap is 2, so 24 was bumped on the way in; active overs = {26, 28}.
      # DQ the 28 and reconcile: the previously-bumped 24 must return alongside 26.
      placed.find { |c| c.length_inches.to_i == 28 }.update!(status: :disqualified)
      ReconcileProWalleye.call(tournament: @t, entry: @entry, species: @walleye)
      assert_equal [24, 26], active_lengths
    end

    test "no eligible catches clears all placements" do
      c = make(20)
      PlaceInSlots.call(catch: c)
      c.update!(status: :disqualified)
      ReconcileProWalleye.call(tournament: @t, entry: @entry, species: @walleye)
      assert_equal 0, @entry.catch_placements.where(active: true).count
    end
  end
end
