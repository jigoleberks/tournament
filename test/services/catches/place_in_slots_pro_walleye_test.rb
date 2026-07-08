require "test_helper"

module Catches
  class PlaceInSlotsProWalleyeTest < ActiveSupport::TestCase
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

    # length_inches: 15-21 are ≤55cm ("under"); 22/24/26/30 are >55cm ("over").
    def place(len)
      PlaceInSlots.call(catch: create(:catch, user: @user, species: @walleye, length_inches: len))
    end

    def active_lengths
      @entry.catch_placements.where(active: true).includes(:catch)
            .map { |p| p.catch.length_inches.to_i }.sort
    end

    test "with no overs, the basket fills up to 5 unders then bumps the smallest" do
      [16, 17, 18, 19, 20].each { |l| place(l) } # 5 unders fill the basket
      place(15)                                   # smaller than the smallest -> no-op
      assert_equal [16, 17, 18, 19, 20], active_lengths
      place(21)                                   # larger under -> bumps the 16
      assert_equal [17, 18, 19, 20, 21], active_lengths
    end

    test "at most 2 overs; a 3rd over bumps the smaller over, never an under" do
      [16, 17, 18].each { |l| place(l) }  # 3 unders
      [24, 26].each { |l| place(l) }       # 2 overs -> full basket
      assert_equal [16, 17, 18, 24, 26], active_lengths
      place(30)                            # 3rd over -> bumps the smallest over (24)
      assert_equal [16, 17, 18, 26, 30], active_lengths
      place(22)                            # over but smaller than smallest over (26) -> no-op
      assert_equal [16, 17, 18, 26, 30], active_lengths
    end

    test "an over bumps the smallest under when the basket is full and overs < 2" do
      [16, 17, 18, 19, 20].each { |l| place(l) } # 5 unders
      place(24)                                   # over -> bumps smallest under (16)
      assert_equal [17, 18, 19, 20, 24], active_lengths
      place(26)                                   # 2nd over -> bumps smallest under (17)
      assert_equal [18, 19, 20, 24, 26], active_lengths
    end
  end
end
