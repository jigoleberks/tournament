require "test_helper"

module Catches
  class DropMemberFromEntryTest < ActiveSupport::TestCase
    setup do
      @club    = create(:club)
      @walleye = create(:species, club: @club)
      @kept    = create(:user, club: @club, name: "Kept")
      @removed = create(:user, club: @club, name: "Removed")
      @t       = create(:tournament, club: @club, mode: :team,
                                     starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 2)
      @entry = create(:tournament_entry, tournament: @t, name: "Boat 1")
      create(:tournament_entry_member, tournament_entry: @entry, user: @kept)
      create(:tournament_entry_member, tournament_entry: @entry, user: @removed)
    end

    test "deactivates the removed user's active placements on the entry" do
      kept_catch    = create(:catch, user: @kept,    species: @walleye, length_inches: 20, captured_at_device: 30.minutes.ago)
      removed_catch = create(:catch, user: @removed, species: @walleye, length_inches: 18, captured_at_device: 25.minutes.ago)
      Catches::PlaceInSlots.call(catch: kept_catch)
      Catches::PlaceInSlots.call(catch: removed_catch)
      assert_equal 1, removed_catch.catch_placements.where(active: true).count

      Catches::DropMemberFromEntry.call(entry: @entry, user: @removed)

      assert_equal 0, removed_catch.catch_placements.where(active: true).count
      assert_equal 1, kept_catch.catch_placements.where(active: true).count
    end

    test "destroys the membership row" do
      assert_difference "TournamentEntryMember.count", -1 do
        Catches::DropMemberFromEntry.call(entry: @entry, user: @removed)
      end
      assert_not @entry.reload.users.include?(@removed)
    end

    test "promotes a backup catch from a remaining team member into the freed slot" do
      slot1 = create(:catch, user: @kept,    species: @walleye, length_inches: 22, captured_at_device: 30.minutes.ago)
      slot2 = create(:catch, user: @removed, species: @walleye, length_inches: 18, captured_at_device: 25.minutes.ago)
      backup = create(:catch, user: @kept,   species: @walleye, length_inches: 16, captured_at_device: 20.minutes.ago)
      Catches::PlaceInSlots.call(catch: slot1)
      Catches::PlaceInSlots.call(catch: slot2)
      Catches::PlaceInSlots.call(catch: backup)
      assert_equal 0, backup.catch_placements.where(active: true).count, "backup should be unplaced before removal"

      Catches::DropMemberFromEntry.call(entry: @entry, user: @removed)

      assert_equal 1, backup.reload.catch_placements.where(active: true).count, "backup should be promoted into freed slot"
    end

    test "BvS: drops a member's extreme placement and reconciles to the remaining members' actual extremes" do
      # Team BvS entry. @kept catches: 22, 16, 12; @removed catches: 10.
      # Incremental placement walks active to [22@?, 10@?] (10 bumps 12 which
      # bumps 16). Drop @removed. PromoteBackup would pick the largest unplaced
      # (16) into the freed slot → [22, 16] (spread 6). Correct BvS: eligible
      # is now {22, 16, 12} → [22, 12] (spread 10).
      bvs = build(:tournament, club: @club, mode: :team, format: :biggest_vs_smallest,
                  kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      bvs.scoring_slots.build(species: @walleye, slot_count: 1)
      bvs.save!
      bvs_entry = create(:tournament_entry, tournament: bvs)
      create(:tournament_entry_member, tournament_entry: bvs_entry, user: @kept)
      create(:tournament_entry_member, tournament_entry: bvs_entry, user: @removed)

      [[@kept, 22, 30.minutes.ago],
       [@kept, 16, 25.minutes.ago],
       [@kept, 12, 20.minutes.ago],
       [@removed, 10, 15.minutes.ago]].each do |user, length, captured|
        Catches::PlaceInSlots.call(
          catch: create(:catch, user: user, species: @walleye,
                                length_inches: length, captured_at_device: captured)
        )
      end
      pre_lens = bvs_entry.catch_placements.where(active: true)
                          .includes(:catch).map { |p| p.catch.length_inches.to_f }.sort
      assert_equal [10.0, 22.0], pre_lens, "preconditions: expected entry's extremes to be [10, 22]"

      Catches::DropMemberFromEntry.call(entry: bvs_entry, user: @removed)

      active_lens = bvs_entry.catch_placements.where(active: true)
                              .includes(:catch).map { |p| p.catch.length_inches.to_f }.sort
      assert_equal [12.0, 22.0], active_lens,
                   "expected biggest 22 and actual smallest 12 — not next-largest 16"
    end

    test "does not promote a backup catch from the removed user" do
      slot1 = create(:catch, user: @kept,    species: @walleye, length_inches: 22, captured_at_device: 30.minutes.ago)
      slot2 = create(:catch, user: @removed, species: @walleye, length_inches: 20, captured_at_device: 25.minutes.ago)
      removed_backup = create(:catch, user: @removed, species: @walleye, length_inches: 18, captured_at_device: 20.minutes.ago)
      Catches::PlaceInSlots.call(catch: slot1)
      Catches::PlaceInSlots.call(catch: slot2)
      Catches::PlaceInSlots.call(catch: removed_backup)

      Catches::DropMemberFromEntry.call(entry: @entry, user: @removed)

      assert_equal 0, removed_backup.reload.catch_placements.where(active: true).count
      assert_equal 1, @entry.catch_placements.where(active: true).count, "only the kept user's slot1 catch remains"
    end

    test "broadcasts the leaderboard once" do
      slot1 = create(:catch, user: @removed, species: @walleye, length_inches: 22, captured_at_device: 30.minutes.ago)
      Catches::PlaceInSlots.call(catch: slot1)

      calls = with_broadcast_spy do
        Catches::DropMemberFromEntry.call(entry: @entry, user: @removed)
      end
      assert_equal [@t.id], calls
    end

    test "is a no-op-on-leaderboard when the removed member had no active placements" do
      kept_catch = create(:catch, user: @kept, species: @walleye, length_inches: 20, captured_at_device: 30.minutes.ago)
      Catches::PlaceInSlots.call(catch: kept_catch)

      Catches::DropMemberFromEntry.call(entry: @entry, user: @removed)

      assert_equal 1, kept_catch.reload.catch_placements.where(active: true).count
      assert_not @entry.reload.users.include?(@removed)
    end
  end
end
