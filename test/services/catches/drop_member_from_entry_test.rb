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

      original = Placements::BroadcastLeaderboard.method(:call)
      calls = []
      Placements::BroadcastLeaderboard.define_singleton_method(:call) { |tournament:| calls << tournament.id }
      begin
        Catches::DropMemberFromEntry.call(entry: @entry, user: @removed)
      ensure
        Placements::BroadcastLeaderboard.define_singleton_method(:call, original)
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
