require "test_helper"

module Catches
  class ApplyJudgeActionTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @judge = create(:user, club: @club, role: :organizer)
      @user = create(:user, club: @club)
      @t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)
      @entry = create(:tournament_entry, tournament: @t)
      create(:tournament_entry_member, tournament_entry: @entry, user: @user)
      @catch = create(:catch, user: @user, species: @walleye, length_inches: 20, status: :needs_review)
      Catches::PlaceInSlots.call(catch: @catch)
    end

    test "approve transitions needs_review -> synced and writes an audit row" do
      assert_difference "JudgeAction.count", 1 do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :approve, note: "ok")
      end
      assert @catch.reload.synced?
    end

    test "approve raises SelfApprovalError when judge is the catch owner" do
      own_catch = create(:catch, user: @judge, species: @walleye, length_inches: 19, status: :needs_review)
      assert_no_difference "JudgeAction.count" do
        assert_raises(ApplyJudgeAction::SelfApprovalError) do
          ApplyJudgeAction.call(tournament: @t, catch: own_catch, judge: @judge, action: :approve, note: "self")
        end
      end
      assert own_catch.reload.needs_review?
    end

    test "disqualify deactivates active placements and re-broadcasts leaderboard" do
      assert @catch.catch_placements.active.exists?
      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :disqualify, note: "bad photo")
      assert @catch.reload.disqualified?
      assert_equal 0, @catch.catch_placements.active.count
    end

    test "disqualify promotes a backup catch into the freed slot" do
      backup = create(:catch, user: @user, species: @walleye, length_inches: 16,
                              captured_at_device: 30.minutes.ago)
      assert_empty backup.catch_placements

      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :disqualify, note: "bad photo")

      assert @catch.reload.disqualified?
      promoted = @t.catch_placements.active.where(species: @walleye).first
      assert_not_nil promoted, "expected a promoted backup placement"
      assert_equal backup.id, promoted.catch_id
    end

    test "disqualify raises DisqualifyNoteRequired when note is blank" do
      assert_no_difference "JudgeAction.count" do
        assert_raises(ApplyJudgeAction::DisqualifyNoteRequired) do
          ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :disqualify, note: "")
        end
      end
      assert @catch.reload.needs_review?
      assert @catch.catch_placements.active.exists?
    end

    test "disqualify raises DisqualifyNoteRequired when note is whitespace only" do
      assert_raises(ApplyJudgeAction::DisqualifyNoteRequired) do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :disqualify, note: "   \n")
      end
    end

    test "dock_verify transitions to synced and notes the manual verification" do
      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :dock_verify, note: "confirmed at dock")
      ja = JudgeAction.last
      assert_equal "dock_verify", ja.action
      assert @catch.reload.synced?
    end

    test "writes before/after state" do
      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :approve, note: nil)
      ja = JudgeAction.last
      assert_equal "needs_review", ja.before_state["status"]
      assert_equal "synced", ja.after_state["status"]
    end

    test "manual_override updates length and writes audit row" do
      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
                            note: "tail squeezed", length_inches: 19.75)
      assert_equal 19.75, @catch.reload.length_inches.to_f
    end

    test "manual_override placing into a slot deactivates whatever is there" do
      # The setup already placed @catch in slot 0 of the only walleye slot; create a second catch and
      # ask for it to take slot 0.
      user2 = create(:user, club: @club)
      entry2 = create(:tournament_entry, tournament: @t)
      create(:tournament_entry_member, tournament_entry: entry2, user: user2)
      alt = create(:catch, user: user2, species: @walleye, length_inches: 16)
      Catches::PlaceInSlots.call(catch: alt)   # places in alt's own entry, not @catch's

      # Force alt into @catch's entry, slot 0
      ApplyJudgeAction.call(
        tournament: @t, catch: alt, judge: @judge, action: :manual_override, note: "judge call",
        slot_index: 0, entry_id: @catch.catch_placements.first.tournament_entry_id
      )
      # @catch should now be inactive in its entry, slot 0
      assert_not @catch.catch_placements.first.reload.active?
    end

    test "manual_override edit-down promotes a previously-unplaced larger catch into the slot" do
      # @catch (20") is in slot 0. A smaller fish (16") never displaced it.
      backup = create(:catch, user: @user, species: @walleye, length_inches: 16,
                              captured_at_device: 30.minutes.ago)
      assert_empty backup.catch_placements

      # Judge edits @catch down to 14" — backup (16") should now take the slot.
      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
                            note: "remeasured", length_inches: 14)

      assert_equal 14.0, @catch.reload.length_inches.to_f
      active = @t.catch_placements.active.where(species: @walleye)
      assert_equal 1, active.count
      assert_equal backup.id, active.first.catch_id
      assert_not @catch.catch_placements.where(slot_index: 0).first.active?
    end

    test "manual_override edit-down does not swap when no larger candidate exists" do
      # Only @catch (20") exists; edit it down to 14". No swap, but length updates.
      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
                            note: "remeasured", length_inches: 14)

      assert_equal 14.0, @catch.reload.length_inches.to_f
      active = @t.catch_placements.active.where(species: @walleye)
      assert_equal 1, active.count
      assert_equal @catch.id, active.first.catch_id
    end

    test "manual_override edit-up does not disturb a smaller unplaced catch" do
      backup = create(:catch, user: @user, species: @walleye, length_inches: 16,
                              captured_at_device: 30.minutes.ago)

      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
                            note: "remeasured", length_inches: 22)

      assert_equal 22.0, @catch.reload.length_inches.to_f
      active = @t.catch_placements.active.where(species: @walleye)
      assert_equal 1, active.count
      assert_equal @catch.id, active.first.catch_id
      assert_empty backup.reload.catch_placements
    end

    test "manual_override rebalances a top-N slot when the edit pushes a placed fish below an unplaced one" do
      # Build a top-3 slot in a fresh tournament with its own user, so the setup
      # @catch can't leak in as a candidate.
      t3 = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: t3, species: @walleye, slot_count: 3)
      angler = create(:user, club: @club)
      entry = create(:tournament_entry, tournament: t3)
      create(:tournament_entry_member, tournament_entry: entry, user: angler)

      # Three placed (24, 22, 20) and one unplaced (18).
      placed = [24, 22, 20].map do |inches|
        c = create(:catch, user: angler, species: @walleye, length_inches: inches,
                           captured_at_device: 30.minutes.ago)
        Catches::PlaceInSlots.call(catch: c)
        c
      end
      unplaced = create(:catch, user: angler, species: @walleye, length_inches: 18,
                                captured_at_device: 30.minutes.ago)
      assert_empty unplaced.catch_placements

      # Edit the 20" fish down to 16" — unplaced 18" should take its slot.
      shrinker = placed.last
      ApplyJudgeAction.call(tournament: t3, catch: shrinker, judge: @judge, action: :manual_override,
                            note: "remeasured", length_inches: 16)

      active_ids = t3.catch_placements.active.where(species: @walleye).pluck(:catch_id)
      assert_equal 3, active_ids.size
      assert_includes active_ids, unplaced.id
      assert_not_includes active_ids, shrinker.id
    end

    test "manual_override rejects an entry that belongs to a different tournament" do
      other_t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      other_entry = create(:tournament_entry, tournament: other_t)

      assert_raises(ActiveRecord::RecordNotFound) do
        ApplyJudgeAction.call(
          tournament: @t, catch: @catch, judge: @judge, action: :manual_override, note: "drive-by",
          slot_index: 0, entry_id: other_entry.id
        )
      end
      assert_equal 0, other_entry.catch_placements.count
    end
  end
end
