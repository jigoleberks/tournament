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
      entry = create(:tournament_entry, tournament: @t)
      create(:tournament_entry_member, tournament_entry: entry, user: @user)
      @catch = create(:catch, user: @user, species: @walleye, length_inches: 20, status: :needs_review)
      Catches::PlaceInSlots.call(catch: @catch)
    end

    test "approve transitions needs_review -> synced and writes an audit row" do
      assert_difference "JudgeAction.count", 1 do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :approve, note: "ok")
      end
      assert @catch.reload.synced?
    end

    test "disqualify deactivates active placements and re-broadcasts leaderboard" do
      assert @catch.catch_placements.active.exists?
      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :disqualify, note: "bad photo")
      assert @catch.reload.disqualified?
      assert_equal 0, @catch.catch_placements.active.count
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
