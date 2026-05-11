require "test_helper"

module Catches
  class ApplyJudgeActionTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @pike = create(:species, club: @club)
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

    test "manual_override species change deactivates old placement, places in new-species slot, promotes backup" do
      create(:scoring_slot, tournament: @t, species: @pike, slot_count: 1)
      walleye_backup = create(:catch, user: @user, species: @walleye, length_inches: 16,
                                       captured_at_device: 30.minutes.ago)
      assert_empty walleye_backup.catch_placements

      ApplyJudgeAction.call(
        tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
        note: "misidentified", species_id: @pike.id
      )

      @catch.reload
      assert_equal @pike.id, @catch.species_id
      old_placement = @t.catch_placements.where(catch_id: @catch.id, species_id: @walleye.id).first
      assert_not_nil old_placement
      assert_not old_placement.active?, "old walleye placement should be deactivated"

      new_placement = @t.catch_placements.where(catch_id: @catch.id, species_id: @pike.id, active: true).first
      assert_not_nil new_placement, "expected an active pike placement"
      assert_equal 0, new_placement.slot_index

      promoted = @t.catch_placements.where(species_id: @walleye.id, active: true).first
      assert_not_nil promoted, "freed walleye slot should have been promoted"
      assert_equal walleye_backup.id, promoted.catch_id
    end

    test "manual_override species change to a species without a scoring slot leaves the catch unplaced" do
      walleye_backup = create(:catch, user: @user, species: @walleye, length_inches: 16,
                                       captured_at_device: 30.minutes.ago)
      assert_empty walleye_backup.catch_placements

      ApplyJudgeAction.call(
        tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
        note: "misidentified", species_id: @pike.id
      )

      @catch.reload
      assert_equal @pike.id, @catch.species_id
      assert_equal 0, @catch.catch_placements.active.count, "no pike scoring slot in this tournament"

      promoted = @t.catch_placements.where(species_id: @walleye.id, active: true).first
      assert_not_nil promoted, "freed walleye slot should be filled by the backup"
      assert_equal walleye_backup.id, promoted.catch_id
    end

    test "manual_override species change on a catch with no active placements is a simple update" do
      # Disqualify the catch first so it has no active placements; PlaceInSlots short-circuits on disqualified.
      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :disqualify, note: "bad photo")
      assert_equal 0, @catch.reload.catch_placements.active.count

      assert_difference "JudgeAction.count", 1 do
        ApplyJudgeAction.call(
          tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
          note: "and also wrong species", species_id: @pike.id
        )
      end
      assert_equal @pike.id, @catch.reload.species_id
      assert_equal 0, @catch.catch_placements.active.count
    end

    test "manual_override combined species and length change" do
      create(:scoring_slot, tournament: @t, species: @pike, slot_count: 1)

      ApplyJudgeAction.call(
        tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
        note: "remeasured + reidentified", species_id: @pike.id, length_inches: 25
      )

      @catch.reload
      assert_equal @pike.id, @catch.species_id
      assert_equal 25.0, @catch.length_inches.to_f
      assert_equal 1, @catch.catch_placements.active.count
      assert_equal @pike.id, @catch.catch_placements.active.first.species_id
    end

    test "manual_override with species_id matching current species does not recompute placements" do
      original_placement_id = @catch.catch_placements.active.first.id

      ApplyJudgeAction.call(
        tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
        note: "no-op species, real length update",
        species_id: @walleye.id, length_inches: 19
      )

      @catch.reload
      assert_equal @walleye.id, @catch.species_id
      assert_equal 19.0, @catch.length_inches.to_f
      assert_equal 1, @catch.catch_placements.active.count
      assert_equal original_placement_id, @catch.catch_placements.active.first.id,
        "existing placement should be reused, not destroyed and recreated"
    end

    test "manual_override species change is captured in audit before/after_state" do
      create(:scoring_slot, tournament: @t, species: @pike, slot_count: 1)

      ApplyJudgeAction.call(
        tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
        note: "misidentified", species_id: @pike.id
      )

      ja = JudgeAction.last
      assert_equal "manual_override", ja.action
      assert_equal @walleye.id, ja.before_state["species_id"]
      assert_equal @walleye.name, ja.before_state["species_name"]
      assert_equal @pike.id, ja.after_state["species_id"]
      assert_equal @pike.name, ja.after_state["species_name"]
    end

    test "manual_override species change re-evaluates other concurrent tournaments the user is in" do
      # Second tournament, walleye-only scoring, same time window, same user has an entry.
      # Place in t2 directly via factory to keep this test focused on species-change behavior
      # rather than on PlaceInSlots's idempotence semantics.
      t2 = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: t2, species: @walleye, slot_count: 1)
      entry2 = create(:tournament_entry, tournament: t2)
      create(:tournament_entry_member, tournament_entry: entry2, user: @user)
      create(:catch_placement, catch: @catch, tournament: t2, tournament_entry: entry2,
                                species: @walleye, slot_index: 0, active: true)

      assert_equal 2, @catch.catch_placements.active.count

      # Add pike scoring to t1 only; t2 still has only walleye.
      create(:scoring_slot, tournament: @t, species: @pike, slot_count: 1)

      ApplyJudgeAction.call(
        tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
        note: "misidentified", species_id: @pike.id
      )

      @catch.reload
      assert_equal @pike.id, @catch.species_id
      # t1 has a pike slot — placed.
      assert @t.catch_placements.where(catch_id: @catch.id, species_id: @pike.id, active: true).exists?
      # t2 has only walleye scoring — catch is now unplaced there.
      assert_equal 0, t2.catch_placements.where(catch_id: @catch.id, active: true).count
    end

    test "manual_override species change with length increase bumps a smaller fish in the new-species slot" do
      create(:scoring_slot, tournament: @t, species: @pike, slot_count: 1)

      # Pre-existing 22" pike in @user's entry occupies pike slot 0.
      existing_pike = create(:catch, user: @user, species: @pike, length_inches: 22,
                                      captured_at_device: 30.minutes.ago)
      Catches::PlaceInSlots.call(catch: existing_pike)
      assert existing_pike.catch_placements.active.where(species: @pike).exists?,
        "precondition: 22\" pike is in pike slot 0"

      # Change @catch from walleye 20" → pike 25" in one submit. The catch's new length (25)
      # should bump the existing 22" pike out of slot 0; the catch's old length (20) would not.
      ApplyJudgeAction.call(
        tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
        note: "misidentified + remeasured", species_id: @pike.id, length_inches: 25
      )

      @catch.reload
      assert_equal @pike.id, @catch.species_id
      assert_equal 25.0, @catch.length_inches.to_f
      pike_slot_holder = @t.catch_placements.active.where(species: @pike, slot_index: 0).first
      assert_not_nil pike_slot_holder, "pike slot should now have an active placement"
      assert_equal @catch.id, pike_slot_holder.catch_id,
        "25\" pike should have bumped the 22\" pike out of slot 0"

      # The bumped existing pike's placement is deactivated.
      existing_pike_placement = existing_pike.catch_placements.where(species: @pike).first
      assert_not existing_pike_placement.active?, "22\" pike should have been bumped"
    end

    # --- Biggest vs Smallest reconciliation paths -----------------------------
    #
    # PromoteBackup / RebalanceSlots assume "fill the freed slot with the
    # largest non-placed catch," which is wrong for BvS when the freed slot
    # was holding the smaller extreme. ApplyJudgeAction has to route BvS
    # placements through Catches::ReconcileBvsExtremes instead.

    def make_bvs_setup
      bvs_user = create(:user, club: @club)
      bvs = build(:tournament, club: @club, format: :biggest_vs_smallest, mode: :solo,
                  kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      bvs.scoring_slots.build(species: @walleye, slot_count: 1)
      bvs.save!
      bvs_entry = create(:tournament_entry, tournament: bvs)
      create(:tournament_entry_member, tournament_entry: bvs_entry, user: bvs_user)
      [bvs, bvs_entry, bvs_user]
    end

    test "BvS: disqualifying the smallest extreme reconciles to the actual next-smallest" do
      bvs, bvs_entry, bvs_user = make_bvs_setup
      # Catches: 22, 10, 14, 12. After incremental placement, active is [22, 10];
      # 14 and 12 were mid-range and dropped (inactive placements may exist for
      # 14/12 if PlaceInSlots created and then deactivated them — for BvS, the
      # service skips mid-range entirely, so there is no inactive row for them).
      catches = [22, 10, 14, 12].each_with_index.map do |len, i|
        c = create(:catch, user: bvs_user, species: @walleye, length_inches: len,
                           captured_at_device: (30 - i).minutes.ago, status: :needs_review)
        Catches::PlaceInSlots.call(catch: c)
        c
      end
      smallest = catches[1]  # the 10" catch

      ApplyJudgeAction.call(tournament: bvs, catch: smallest, judge: @judge,
                            action: :disqualify, note: "blurry photo")

      active_lens = bvs_entry.catch_placements.where(active: true)
                              .includes(:catch).map { |p| p.catch.length_inches.to_f }.sort
      assert_equal [12.0, 22.0], active_lens,
                   "expected biggest 22 and actual remaining smallest 12 — not next-largest 14"
    end

    test "BvS: disqualifying the biggest extreme reconciles to the actual next-biggest" do
      bvs, bvs_entry, bvs_user = make_bvs_setup
      catches = [22, 10, 14, 12].each_with_index.map do |len, i|
        c = create(:catch, user: bvs_user, species: @walleye, length_inches: len,
                           captured_at_device: (30 - i).minutes.ago, status: :needs_review)
        Catches::PlaceInSlots.call(catch: c)
        c
      end
      biggest = catches[0]  # the 22" catch

      ApplyJudgeAction.call(tournament: bvs, catch: biggest, judge: @judge,
                            action: :disqualify, note: "out of bounds")

      active_lens = bvs_entry.catch_placements.where(active: true)
                              .includes(:catch).map { |p| p.catch.length_inches.to_f }.sort
      assert_equal [10.0, 14.0], active_lens,
                   "expected new biggest 14 and unchanged smallest 10"
    end

    test "BvS: manual_override species-change reconciles the prior species's extremes" do
      bvs, bvs_entry, bvs_user = make_bvs_setup
      catches = [22, 10, 14, 12].each_with_index.map do |len, i|
        c = create(:catch, user: bvs_user, species: @walleye, length_inches: len,
                           captured_at_device: (30 - i).minutes.ago, status: :needs_review)
        Catches::PlaceInSlots.call(catch: c)
        c
      end
      smallest = catches[1]  # the 10" catch — currently the entry's smallest

      ApplyJudgeAction.call(tournament: bvs, catch: smallest, judge: @judge,
                            action: :manual_override, note: "misidentified",
                            species_id: @pike.id)

      active_lens = bvs_entry.catch_placements.where(active: true, species_id: @walleye.id)
                              .includes(:catch).map { |p| p.catch.length_inches.to_f }.sort
      assert_equal [12.0, 22.0], active_lens,
                   "expected walleye BvS to reconcile to [22, 12] after the 10\" moved to pike"
    end

    test "BvS: manual_override length-shrink re-derives both extremes from the eligible catch set" do
      bvs, bvs_entry, bvs_user = make_bvs_setup
      # Active becomes [22, 12]; 14 is mid-range (dropped). Edit 22 down to 13.
      # Old RebalanceSlots would produce [13, 14] (largest-unplaced fills the
      # smallest active slot). Correct BvS: eligible = {13, 14, 12} → [14, 12].
      [22, 12, 14].each_with_index do |len, i|
        Catches::PlaceInSlots.call(
          catch: create(:catch, user: bvs_user, species: @walleye, length_inches: len,
                                captured_at_device: (30 - i).minutes.ago, status: :synced)
        )
      end
      shrinker = ::Catch.find_by!(length_inches: 22, user_id: bvs_user.id)

      ApplyJudgeAction.call(tournament: bvs, catch: shrinker, judge: @judge,
                            action: :manual_override, note: "remeasured", length_inches: 13)

      active_lens = bvs_entry.catch_placements.where(active: true)
                              .includes(:catch).map { |p| p.catch.length_inches.to_f }.sort
      assert_equal [12.0, 14.0], active_lens,
                   "expected biggest 14 and smallest 12 after the 22 shrank to 13"
    end
  end
end
