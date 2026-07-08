require "test_helper"

module Catches
  # ReconcileFreedSlot dispatches by format. These pin the behaviour so the
  # "delegate the re-derive formats to ReconcileBasket" consolidation stays
  # behaviour-preserving: the Standard family keeps the cheap single-slot
  # PromoteBackup, the re-derive formats rebuild the whole basket, and the
  # every-catch-placed formats (Hidden Length / Tagged) never refill a hole.
  class ReconcileFreedSlotTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, name: "Walleye")
      @user = create(:user, club: @club)
    end

    def build_tournament(format, slot_count: 2, species: @walleye)
      t = build(:tournament, club: @club, format: format,
                starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      t.scoring_slots.build(species: species, slot_count: slot_count)
      t.save!
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: @user)
      [t, entry]
    end

    def place(len, tag: nil, captured: 30.minutes.ago, species: @walleye)
      c = create(:catch, user: @user, species: species, length_inches: len,
                 tag_number: tag, captured_at_device: captured)
      PlaceInSlots.call(catch: c)
      c
    end

    def active_lengths(entry)
      entry.catch_placements.where(active: true).includes(:catch)
           .map { |p| p.catch.length_inches.to_i }.sort
    end

    def dq_placement(catch_record, entry)
      placement = entry.catch_placements.active.find_by(catch_id: catch_record.id)
      catch_record.update!(status: :disqualified)
      placement.update!(active: false)
      placement
    end

    test "standard: freeing a slot promotes the largest backup (single-slot refill)" do
      t, entry = build_tournament(:standard, slot_count: 2)
      place(22, captured: 40.minutes.ago)
      keep_small = place(18, captured: 35.minutes.ago)
      # Two backups too small to have been placed into the full top-2 basket.
      place(14, captured: 30.minutes.ago)  # smaller backup
      place(16, captured: 25.minutes.ago)  # larger backup
      assert_equal [18, 22], active_lengths(entry)

      freed = dq_placement(keep_small, entry)
      ReconcileFreedSlot.call(placement: freed)

      # PromoteBackup fills the single freed slot with the LARGEST backup (16).
      assert_equal [16, 22], active_lengths(entry)
    end

    test "big_fish_season: freeing a slot promotes the largest backup (single-slot refill)" do
      t, entry = build_tournament(:big_fish_season, slot_count: 2)
      place(22, captured: 40.minutes.ago)
      keep = place(18, captured: 35.minutes.ago)
      place(14, captured: 30.minutes.ago)
      place(16, captured: 25.minutes.ago)
      assert_equal [18, 22], active_lengths(entry)

      freed = dq_placement(keep, entry)
      ReconcileFreedSlot.call(placement: freed)

      assert_equal [16, 22], active_lengths(entry)
    end

    test "smallest_fish: freeing a slot re-derives the basket (promotes the SMALLER backup)" do
      t, entry = build_tournament(:smallest_fish, slot_count: 2)
      # Smallest Fish keeps the two smallest; 8 and 10 fill the basket.
      place(8, captured: 40.minutes.ago)
      keep_smallest = place(10, captured: 35.minutes.ago)
      # Backups larger than the basket — never placed incrementally.
      place(20, captured: 30.minutes.ago)  # smaller backup
      place(30, captured: 25.minutes.ago)  # larger backup
      assert_equal [8, 10], active_lengths(entry)

      freed = dq_placement(keep_smallest, entry)
      ReconcileFreedSlot.call(placement: freed)

      # A whole-basket re-derive keeps the two smallest of {8, 20, 30} => [8, 20].
      # (PromoteBackup would have wrongly promoted the largest, 30.)
      assert_equal [8, 20], active_lengths(entry)
    end

    test "hidden_length: freeing a slot never refills it" do
      t, entry = build_tournament(:hidden_length, slot_count: 1)
      # Hidden Length places every catch; there is no backup pool.
      first = place(22, captured: 40.minutes.ago)
      place(16, captured: 35.minutes.ago)
      place(14, captured: 30.minutes.ago)
      assert_equal [14, 16, 22], active_lengths(entry)

      freed = dq_placement(first, entry)
      ReconcileFreedSlot.call(placement: freed)

      # The freed slot stays empty — no promotion, the survivors are untouched.
      assert_equal [14, 16], active_lengths(entry)
    end

    test "tagged: freeing a slot never refills it" do
      tagged = Species.find_or_create_by!(name: "Tagged Walleye")
      t, entry = build_tournament(:tagged, slot_count: 1, species: tagged)
      first = place(22, tag: "A0001", captured: 40.minutes.ago, species: tagged)
      place(16, tag: "A0002", captured: 35.minutes.ago, species: tagged)
      assert_equal [16, 22], active_lengths(entry)

      freed = dq_placement(first, entry)
      ReconcileFreedSlot.call(placement: freed)

      assert_equal [16], active_lengths(entry)
    end
  end
end
