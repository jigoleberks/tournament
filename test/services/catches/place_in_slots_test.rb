require "test_helper"

module Catches
  class PlaceInSlotsTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club, name: "Walleye")
      @user = create(:user, club: @club)
      @tournament = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: @tournament, species: @walleye, slot_count: 2)
      @entry = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: @entry, user: @user)
    end

    test "places a single fish into the first empty slot of its species" do
      catch_record = create(:catch, user: @user, species: @walleye, length_inches: 20)
      result = PlaceInSlots.call(catch: catch_record)

      placement = catch_record.catch_placements.sole
      assert_equal @entry, placement.tournament_entry
      assert_equal @walleye, placement.species
      assert_equal 0, placement.slot_index
      assert placement.active?
      assert_includes result[:created], placement
    end

    test "fills slot_index 1 when slot 0 is occupied" do
      first = create(:catch, user: @user, species: @walleye, length_inches: 14)
      PlaceInSlots.call(catch: first)
      second = create(:catch, user: @user, species: @walleye, length_inches: 17)
      PlaceInSlots.call(catch: second)

      assert_equal [0, 1], CatchPlacement.where(tournament_entry: @entry, active: true).order(:slot_index).pluck(:slot_index)
    end

    test "ignores tournaments that don't score this species" do
      perch = create(:species, club: @club, name: "Perch")
      catch_record = create(:catch, user: @user, species: perch, length_inches: 10)
      result = PlaceInSlots.call(catch: catch_record)
      assert_empty result[:created]
    end

    test "when all slots are full, replaces the smallest active fish if new is bigger" do
      small = create(:catch, user: @user, species: @walleye, length_inches: 14)
      PlaceInSlots.call(catch: small)
      medium = create(:catch, user: @user, species: @walleye, length_inches: 17)
      PlaceInSlots.call(catch: medium)
      big = create(:catch, user: @user, species: @walleye, length_inches: 22)
      result = PlaceInSlots.call(catch: big)

      assert_includes result[:bumped], small.catch_placements.first
      assert_not small.catch_placements.first.reload.active?
      assert_equal [17, 22],
        CatchPlacement.active.where(tournament_entry: @entry).joins(:catch).order("catches.length_inches").pluck("catches.length_inches").map(&:to_i)
    end

    test "when all slots are full and new fish is smaller, no placement is made" do
      big1 = create(:catch, user: @user, species: @walleye, length_inches: 22)
      big2 = create(:catch, user: @user, species: @walleye, length_inches: 21)
      small = create(:catch, user: @user, species: @walleye, length_inches: 10)
      PlaceInSlots.call(catch: big1)
      PlaceInSlots.call(catch: big2)
      result = PlaceInSlots.call(catch: small)

      assert_empty result[:created]
      assert_empty result[:bumped]
      assert small.catch_placements.empty?
    end

    test "credits multiple active tournaments — boat entry and individual entry" do
      # Boat tournament (team mode)
      boat_tournament = create(:tournament, club: @club, mode: :team,
                                starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: boat_tournament, species: @walleye, slot_count: 2)
      boat = create(:tournament_entry, tournament: boat_tournament, name: "Curtis's Boat")
      create(:tournament_entry_member, tournament_entry: boat, user: @user)

      # Individual ongoing tournament (already set up in setup as @tournament + @entry)
      catch_record = create(:catch, user: @user, species: @walleye, length_inches: 20)
      result = PlaceInSlots.call(catch: catch_record)

      assert_equal 2, result[:created].size
      entries = result[:created].map(&:tournament_entry).sort_by(&:id)
      assert_equal [@entry, boat].sort_by(&:id), entries
    end

    test "does not place a catch logged before the angler joined the entry" do
      # late_user gets their own solo entry; backdate its membership so it predates
      # the tournament start, then log a catch that predates the membership.
      late_user = create(:user, club: @club)
      late_entry = create(:tournament_entry, tournament: @tournament)
      late_member = create(:tournament_entry_member, tournament_entry: late_entry, user: late_user)
      late_member.update_column(:created_at, 30.minutes.ago)
      pre_join = create(:catch, user: late_user, species: @walleye, length_inches: 30,
                                captured_at_device: 1.hour.ago)
      Catches::PlaceInSlots.call(catch: pre_join)
      assert_empty pre_join.catch_placements
    end
  end
end
