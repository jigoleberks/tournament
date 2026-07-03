require "test_helper"

module Catches
  class ReconcileStandardTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, name: "Walleye")
      @user = create(:user, club: @club)
      @t = build(:tournament, club: @club, format: :standard, mode: :solo,
                 starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      @t.scoring_slots.build(species: @walleye, slot_count: 2)
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

    test "more eligible than slots: keeps the N largest" do
      [8, 9, 14, 20].each { |l| PlaceInSlots.call(catch: make(l)) }
      ReconcileStandard.call(tournament: @t, entry: @entry, species: @walleye)
      assert_equal [14, 20], active_lengths
    end

    test "fewer eligible than slots: keeps all of them" do
      PlaceInSlots.call(catch: make(8))
      ReconcileStandard.call(tournament: @t, entry: @entry, species: @walleye)
      assert_equal [8], active_lengths
    end

    test "re-derives from scratch: a previously-bumped catch returns when a larger one is DQ'd" do
      c8  = make(8,  captured: 40.minutes.ago)
      c14 = make(14, captured: 30.minutes.ago)
      c20 = make(20, captured: 20.minutes.ago)
      [c8, c14, c20].each { |c| PlaceInSlots.call(catch: c) } # basket {14,20}; 8 bumped
      c20.update!(status: :disqualified)
      ReconcileStandard.call(tournament: @t, entry: @entry, species: @walleye)
      assert_equal [8, 14], active_lengths
    end

    test "no eligible catches clears all placements" do
      c = make(10)
      PlaceInSlots.call(catch: c)
      c.update!(status: :disqualified)
      ReconcileStandard.call(tournament: @t, entry: @entry, species: @walleye)
      assert_equal 0, @entry.catch_placements.where(active: true).count
    end
  end
end
