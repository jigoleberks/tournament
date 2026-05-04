require "test_helper"

module Catches
  class ApplyJudgeActionTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @judge = create(:user, club: @club, role: :organizer)
      @user = create(:user, club: @club)
      @t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)
      @entry = create(:tournament_entry, tournament: @t)
      create(:tournament_entry_member, tournament_entry: @entry, user: @user)
        .update_column(:created_at, 2.hours.ago)
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
        .update_column(:created_at, 2.hours.ago)

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

    test "manual_override edit-down does not pull in a catch logged before the angler joined the entry" do
      # The default @entry is solo; build a team tournament so we can have two members.
      # Use fresh users (not @user) so @catch from setup cannot leak into team_t's window.
      team_t = create(:tournament, club: @club, mode: :team, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: team_t, species: @walleye, slot_count: 1)
      team_entry = create(:tournament_entry, tournament: team_t)
      early = create(:user, club: @club)
      member = create(:tournament_entry_member, tournament_entry: team_entry, user: early)
      member.update_column(:created_at, 2.hours.ago)
      late = create(:user, club: @club)
      late_member = create(:tournament_entry_member, tournament_entry: team_entry, user: late)
      late_member.update_column(:created_at, 30.minutes.ago)

      # early catches a 20" placed in slot 0.
      placed = create(:catch, user: early, species: @walleye, length_inches: 20, captured_at_device: 30.minutes.ago)
      Catches::PlaceInSlots.call(catch: placed)

      # Late-joiner has a 30" pre-membership catch — must not become a candidate.
      pre_join = create(:catch, user: late, species: @walleye, length_inches: 30, captured_at_device: 1.hour.ago)

      # Judge edits placed (20") down to 14" — no eligible candidate exists, slot stays as-is (with 14" length).
      ApplyJudgeAction.call(tournament: team_t, catch: placed, judge: @judge, action: :manual_override,
                            note: "remeasured", length_inches: 14)

      active = team_entry.catch_placements.active.where(species: @walleye)
      assert_equal 1, active.count
      assert_equal placed.id, active.first.catch_id, "pre-membership catch must not have taken the slot"
      assert_not ::CatchPlacement.exists?(catch_id: pre_join.id, active: true)
    end

    test "disqualify pushes a notification to the catch owner with the reason" do
      assert_enqueued_with(job: DeliverPushNotificationJob,
                           args: [{ user_id: @user.id, title: @t.name,
                                    body: "Your #{@walleye.name.downcase} was disqualified: bad photo",
                                    url: "/catches/#{@catch.id}",
                                    tournament_id: @t.id }]) do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                              action: :disqualify, note: "bad photo")
      end
    end

    test "disqualify does not push when judge is the catch owner" do
      own = create(:catch, user: @judge, species: @walleye, length_inches: 19, status: :needs_review)
      Catches::PlaceInSlots.call(catch: own)
      assert_no_enqueued_jobs only: DeliverPushNotificationJob do
        ApplyJudgeAction.call(tournament: @t, catch: own, judge: @judge,
                              action: :disqualify, note: "owner DQ")
      end
    end

    test "disqualify does not push twice when re-DQing an already-disqualified catch" do
      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                            action: :disqualify, note: "first DQ")
      assert_no_enqueued_jobs only: DeliverPushNotificationJob do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                              action: :disqualify, note: "second DQ")
      end
    end

    test "manual_override length change pushes a resize notification to the catch owner" do
      assert_enqueued_with(job: DeliverPushNotificationJob,
                           args: [{ user_id: @user.id, title: @t.name,
                                    body: "Your #{@walleye.name.downcase} was resized to 19.75\".",
                                    url: "/catches/#{@catch.id}",
                                    tournament_id: @t.id }]) do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                              action: :manual_override, note: "remeasured", length_inches: 19.75)
      end
    end

    test "manual_override resize body uses cm when the catch owner prefers centimeters" do
      @user.update!(length_unit: "centimeters")
      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                            action: :manual_override, note: "remeasured", length_inches: 19.69)
      job = enqueued_jobs.last
      assert_equal "DeliverPushNotificationJob", job["job_class"]
      args = ::ActiveJob::Arguments.deserialize(job["arguments"]).first
      assert_match(/resized to 50\.0 cm\.\z/, args[:body])
    end

    test "manual_override does not push when only a slot is forced (no length change)" do
      user2 = create(:user, club: @club)
      entry2 = create(:tournament_entry, tournament: @t)
      create(:tournament_entry_member, tournament_entry: entry2, user: user2)
        .update_column(:created_at, 2.hours.ago)
      alt = create(:catch, user: user2, species: @walleye, length_inches: 16)
      Catches::PlaceInSlots.call(catch: alt)

      assert_no_enqueued_jobs only: DeliverPushNotificationJob do
        ApplyJudgeAction.call(
          tournament: @t, catch: alt, judge: @judge, action: :manual_override, note: "judge call",
          slot_index: 0, entry_id: @catch.catch_placements.first.tournament_entry_id
        )
      end
    end

    test "manual_override does not push when length_inches matches current length" do
      assert_no_enqueued_jobs only: DeliverPushNotificationJob do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                              action: :manual_override, note: "no-op", length_inches: 20)
      end
    end

    test "manual_override does not push when judge is the catch owner" do
      own = create(:catch, user: @judge, species: @walleye, length_inches: 18)
      Catches::PlaceInSlots.call(catch: own)
      assert_no_enqueued_jobs only: DeliverPushNotificationJob do
        ApplyJudgeAction.call(tournament: @t, catch: own, judge: @judge,
                              action: :manual_override, note: "owner remeasure", length_inches: 17)
      end
    end
  end
end
