require "test_helper"

# Fish Train is append-only: a DQ, member-drop, or length edit must NOT refill
# the freed car from a backup catch. The freed car stays a permanent hole; the
# angler recovers by catching forward. See place_in_slots.rb fish_train branch.
module Catches
  class FishTrainReconcileTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club, name: "Walleye")
      @pike = create(:species, club: @club, name: "Pike")
      @judge = create(:user, club: @club, role: :organizer)
      @user = create(:user, club: @club)
    end

    def build_train(cars, mode: :solo)
      t = build(:tournament, club: @club, format: :fish_train, mode: mode,
                starts_at: 1.hour.ago, ends_at: 1.hour.from_now, train_cars: cars)
      cars.uniq.each { |sp_id| t.scoring_slots.build(species_id: sp_id, slot_count: 1) }
      t.save!
      entry = create(:tournament_entry, tournament: t)
      [t, entry]
    end

    def log(t, species, len, min_ago, user: @user)
      c = create(:catch, user: user, species: species, length_inches: len,
                 captured_at_device: min_ago.minutes.ago, status: :needs_review)
      Catches::PlaceInSlots.call(catch: c)
      c
    end

    def active(t)
      CatchPlacement.where(tournament: t, active: true).includes(:catch).order(:slot_index)
        .map { |p| [p.slot_index, p.catch.length_inches.to_i] }
    end

    test "DQ in a locked past group leaves the freed car empty" do
      t, entry = build_train([@walleye.id, @pike.id, @pike.id])
      create(:tournament_entry_member, tournament_entry: entry, user: @user)
      w1 = log(t, @walleye, 20, 50)   # slot 0 (walleye group)
      log(t, @walleye, 18, 40)        # backup, unplaced
      log(t, @pike, 15, 30)           # advances to pike group; walleye group locked
      ApplyJudgeAction.call(tournament: t, catch: w1, judge: @judge, action: :disqualify, note: "x")
      assert_equal [[1, 15]], active(t)
    end

    test "DQ at slot 0 of the current group leaves a hole, no backup promoted" do
      t, entry = build_train([@walleye.id, @walleye.id, @walleye.id])
      create(:tournament_entry_member, tournament_entry: entry, user: @user)
      w1 = log(t, @walleye, 20, 50)
      log(t, @walleye, 18, 40)
      log(t, @walleye, 16, 30)        # full [20@0, 18@1, 16@2]
      log(t, @walleye, 22, 20)        # bumps 16; [20@0, 18@1, 22@2], 16 unplaced
      ApplyJudgeAction.call(tournament: t, catch: w1, judge: @judge, action: :disqualify, note: "x")
      assert_equal [[1, 18], [2, 22]], active(t)
    end

    test "DQ of a middle car leaves a hole, no backup promoted" do
      t, entry = build_train([@walleye.id, @walleye.id, @walleye.id])
      create(:tournament_entry_member, tournament_entry: entry, user: @user)
      log(t, @walleye, 20, 55)
      w2 = log(t, @walleye, 18, 45)
      log(t, @walleye, 16, 35)        # full [20@0, 18@1, 16@2]
      log(t, @walleye, 22, 25)        # bumps 16; [20@0, 18@1, 22@2], 16 unplaced
      ApplyJudgeAction.call(tournament: t, catch: w2, judge: @judge, action: :disqualify, note: "x")
      assert_equal [[0, 20], [2, 22]], active(t)
    end

    test "dropping a member leaves their car empty, no teammate backup promoted" do
      member_b = create(:user, club: @club)
      t, entry = build_train([@walleye.id, @walleye.id, @walleye.id], mode: :team)
      create(:tournament_entry_member, tournament_entry: entry, user: @user)
      create(:tournament_entry_member, tournament_entry: entry, user: member_b)
      log(t, @walleye, 20, 55)               # A -> slot 0
      log(t, @walleye, 18, 45)               # A -> slot 1
      log(t, @walleye, 16, 35)               # A -> slot 2 (full)
      log(t, @walleye, 22, 25, user: member_b) # B bumps 16; [20@0, 18@1, 22@2], A16 unplaced
      Catches::DropMemberFromEntry.call(entry: entry, user: member_b)
      assert_equal [[0, 20], [1, 18]], active(t)
    end

    test "length-shrink edit keeps the edited catch in its car, no backup promoted" do
      t, entry = build_train([@walleye.id, @walleye.id, @walleye.id])
      create(:tournament_entry_member, tournament_entry: entry, user: @user)
      log(t, @walleye, 20, 55)
      log(t, @walleye, 18, 45)
      log(t, @walleye, 16, 35)        # full [20@0, 18@1, 16@2]
      top = log(t, @walleye, 22, 25)  # bumps 16; [20@0, 18@1, 22@2], 16 unplaced
      ApplyJudgeAction.call(tournament: t, catch: top, judge: @judge,
                            action: :manual_override, length_inches: 5, note: "remeasure")
      # The shrunk catch stays in its car; the unplaced 16 is NOT promoted.
      assert_equal [[0, 20], [1, 18], [2, 5]], active(t)
    end
  end
end
