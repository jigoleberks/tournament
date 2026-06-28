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

    # Captures DeliverPushNotificationJob.perform_later kwargs during the block.
    def capture_pushes
      pushes = []
      original = DeliverPushNotificationJob.method(:perform_later)
      DeliverPushNotificationJob.define_singleton_method(:perform_later) { |**kw| pushes << kw }
      yield
      pushes
    ensure
      DeliverPushNotificationJob.singleton_class.send(:remove_method, :perform_later)
      DeliverPushNotificationJob.define_singleton_method(:perform_later, original)
    end

    test "disqualify notifies the catch owner" do
      pushes = capture_pushes do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :disqualify, note: "bad photo")
      end
      owner = pushes.find { |p| p[:user_id] == @user.id }
      assert owner, "expected a push to the catch owner"
      assert_equal @t.id, owner[:tournament_id]
      assert_equal "/tournaments/#{@t.id}", owner[:url]
      assert_match(/disqualified/i, owner[:body])
    end

    test "manual_override that changes length notifies the owner" do
      pushes = capture_pushes do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                              action: :manual_override, note: "remeasured", length_inches: 18)
      end
      owner = pushes.find { |p| p[:user_id] == @user.id }
      assert owner, "expected a push to the catch owner"
      assert_match(/adjusted/i, owner[:body])
    end

    test "manual_override that changes species notifies the owner" do
      pushes = capture_pushes do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                              action: :manual_override, note: "mis-id", species_id: @pike.id)
      end
      assert pushes.any? { |p| p[:user_id] == @user.id }, "expected a push to the catch owner"
    end

    test "no-op manual_override (length unchanged) does not notify" do
      pushes = capture_pushes do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                              action: :manual_override, note: "no change", length_inches: 20)
      end
      assert_empty pushes.select { |p| p[:user_id] == @user.id }
    end

    test "manual_override that changes only the unit persists it and notifies the owner" do
      @catch.update!(length_unit: "inches")
      pushes = capture_pushes do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                              action: :manual_override, note: "logged in cm",
                              length_inches: 20, length_unit: "centimeters")
      end
      assert_equal "centimeters", @catch.reload.length_unit
      assert_equal 20.0, @catch.length_inches.to_f
      assert pushes.any? { |p| p[:user_id] == @user.id }, "expected a push to the catch owner"
    end

    test "approve does not notify the owner" do
      pushes = capture_pushes do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :approve, note: "ok")
      end
      assert_empty pushes
    end

    test "flag does not notify the owner" do
      pushes = capture_pushes do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :flag, note: "look again")
      end
      assert_empty pushes
    end

    test "disqualifying one's own catch does not notify self" do
      own = create(:catch, user: @judge, species: @walleye, length_inches: 19, status: :needs_review)
      Catches::PlaceInSlots.call(catch: own)
      pushes = capture_pushes do
        ApplyJudgeAction.call(tournament: @t, catch: own, judge: @judge, action: :disqualify, note: "mine")
      end
      assert_empty pushes.select { |p| p[:user_id] == @judge.id }
    end

    test "snapshot reuses the loaded species across before/after instead of re-querying" do
      # The before/after snapshots should share one species read (the memoized
      # association) rather than each issuing its own Species.find_by. The lone
      # remaining species query here is the leaderboard rebuild's own preload.
      species_queries = count_queries(/\bfrom\s+"?species"?/i) do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                              action: :manual_override, length_inches: 20, note: "no change")
      end
      assert_operator species_queries, :<=, 2,
                      "snapshot should not double-query species, got #{species_queries} queries"
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

    test "manual_override species can be changed repeatedly, including back to a prior species" do
      create(:scoring_slot, tournament: @t, species: @pike, slot_count: 1)

      ApplyJudgeAction.call(
        tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
        note: "misidentified", species_id: @pike.id
      )
      assert_equal @pike.id, @catch.reload.species_id

      # Undo a misclick: change it straight back to the original species.
      ApplyJudgeAction.call(
        tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
        note: "actually a walleye", species_id: @walleye.id
      )
      assert_equal @walleye.id, @catch.reload.species_id
      assert @t.catch_placements.where(catch_id: @catch.id, species_id: @walleye.id, active: true).exists?,
        "expected an active walleye placement after changing the species back"

      # And once more, to confirm there is no limit on the number of changes.
      ApplyJudgeAction.call(
        tournament: @t, catch: @catch, judge: @judge, action: :manual_override,
        note: "no, pike", species_id: @pike.id
      )
      assert_equal @pike.id, @catch.reload.species_id
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
                  starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
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

    # --- Smallest Fish reconciliation paths -----------------------------------
    #
    # PromoteBackup / RebalanceSlots assume "promote the largest," which corrupts
    # a Smallest Fish basket toward larger fish. ApplyJudgeAction has to route
    # Smallest Fish placements through Catches::ReconcileSmallestFish, which
    # re-derives the N smallest from the whole eligible set.

    def make_smallest_fish_setup
      sf_user = create(:user, club: @club)
      sf = build(:tournament, club: @club, format: :smallest_fish, mode: :solo,
                 starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      sf.scoring_slots.build(species: @walleye, slot_count: 2)
      sf.save!
      sf_entry = create(:tournament_entry, tournament: sf)
      create(:tournament_entry_member, tournament_entry: sf_entry, user: sf_user)
      [sf, sf_entry, sf_user]
    end

    test "smallest_fish: DQ promotes the smallest eligible replacement, not the largest" do
      t, entry, owner = make_smallest_fish_setup

      c8  = create(:catch, user: owner, species: @walleye, length_inches: 8,  captured_at_device: 40.minutes.ago)
      c9  = create(:catch, user: owner, species: @walleye, length_inches: 9,  captured_at_device: 30.minutes.ago)
      c14 = create(:catch, user: owner, species: @walleye, length_inches: 14, captured_at_device: 20.minutes.ago)
      c20 = create(:catch, user: owner, species: @walleye, length_inches: 20, captured_at_device: 10.minutes.ago)
      [c8, c9, c14, c20].each { |c| Catches::PlaceInSlots.call(catch: c) }
      # basket {8,9}; 14 and 20 bumped (>= largest). DQ the 9.

      Catches::ApplyJudgeAction.call(tournament: t, catch: c9, judge: @judge, action: :disqualify, note: "test")

      active = entry.catch_placements.where(active: true).includes(:catch).map { |p| p.catch.length_inches.to_i }.sort
      # eligible now {8,14,20}; two smallest = {8,14}. NOT {8,20} (which the buggy promote-largest path would pick).
      assert_equal [8, 14], active
    end

    test "smallest_fish: growing a placed catch yields its slot to a smaller unplaced catch" do
      t, entry, owner = make_smallest_fish_setup

      c8  = create(:catch, user: owner, species: @walleye, length_inches: 8,  captured_at_device: 40.minutes.ago)
      c9  = create(:catch, user: owner, species: @walleye, length_inches: 9,  captured_at_device: 30.minutes.ago)
      c14 = create(:catch, user: owner, species: @walleye, length_inches: 14, captured_at_device: 20.minutes.ago)
      [c8, c9, c14].each { |c| Catches::PlaceInSlots.call(catch: c) }
      # basket {8,9}; 14 unplaced. Grow the 8 to 18.

      Catches::ApplyJudgeAction.call(tournament: t, catch: c8, judge: @judge, action: :manual_override, note: "test", length_inches: 18)

      active = entry.catch_placements.where(active: true).includes(:catch).map { |p| p.catch.length_inches.to_i }.sort
      # eligible {18,9,14}; two smallest = {9,14}; grown catch (18) drops out.
      assert_equal [9, 14], active
    end

    # --- Admin reference photo ------------------------------------------------
    #
    # add_reference_photo attaches an admin-only secondary photo to a catch
    # WITHOUT touching the original submission photo, flips the catch back to
    # needs_review, and records the change in the audit log.

    def sample_upload
      {
        io: File.open(Rails.root.join("test/fixtures/files/sample_walleye.jpg")),
        filename: "sample_walleye.jpg",
        content_type: "image/jpeg"
      }
    end

    test "add_reference_photo attaches a reference photo, preserves the original, and resets to needs_review" do
      @catch.photo.attach(sample_upload)
      @catch.update!(status: :synced)
      original_blob_id = @catch.photo.blob.id

      assert_difference "JudgeAction.count", 1 do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                              action: :add_reference_photo, note: "clearer angle", photo: sample_upload)
      end

      @catch.reload
      assert @catch.reference_photo.attached?, "reference photo should be attached"
      assert @catch.photo.attached?, "original submission photo should still be attached"
      assert_equal original_blob_id, @catch.photo.blob.id, "original photo blob must be untouched"
      assert @catch.needs_review?, "status should flip back to needs_review"
      assert_equal "add_reference_photo", JudgeAction.last.action
    end

    test "add_reference_photo audit captures reference photo blob ids with no predecessor on first add" do
      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                            action: :add_reference_photo, note: nil, photo: sample_upload)
      ja = JudgeAction.last
      assert_not ja.before_state["reference_photo_attached"], "no reference photo before the action"
      assert ja.after_state["reference_photo_attached"], "reference photo present after the action"
      assert_not_nil ja.after_state["reference_photo_blob_id"]
      assert_nil ja.after_state["reference_photo_prev_blob_id"], "first reference photo has no predecessor"
    end

    test "add_reference_photo replacing an existing reference photo records the prior blob id" do
      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                            action: :add_reference_photo, note: nil, photo: sample_upload)
      first_blob_id = @catch.reload.reference_photo.blob.id

      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                            action: :add_reference_photo, note: nil, photo: sample_upload)
      ja = JudgeAction.last
      assert_equal first_blob_id, ja.after_state["reference_photo_prev_blob_id"]
      assert_not_equal first_blob_id, ja.after_state["reference_photo_blob_id"]
    end

    # --- geofence_override action ---------------------------------------------

    test "geofence_override forces an out-of-province catch to place and clears its flags" do
      oop = create(:catch, user: @user, species: @walleye, length_inches: 25,
                           latitude: 49.9, longitude: -97.1, status: :needs_review)
      Catches::PlaceInSlots.call(catch: oop)
      assert_equal 0, oop.catch_placements.active.count, "out-of-province catch should not place"

      assert_difference "JudgeAction.count", 1 do
        ApplyJudgeAction.call(tournament: @t, catch: oop, judge: @judge,
                              action: :geofence_override, override_in_lake: true, override_in_sask: true)
      end

      oop.reload
      assert oop.override_in_lake
      assert oop.override_in_sask
      assert_equal 1, oop.catch_placements.active.count, "override should place it (bumping the 20)"
      assert_not_includes oop.flags, "out_of_province"
      assert_not_includes oop.flags, "out_of_bounds"
      assert_equal "geofence_override", JudgeAction.last.action
    end

    test "geofence_override preserves the imported_photo flag while clearing geofence flags" do
      oop = create(:catch, user: @user, species: @walleye, length_inches: 25,
                           latitude: 49.9, longitude: -97.1, status: :needs_review,
                           flags: ["out_of_province", "out_of_bounds", "imported_photo"])

      ApplyJudgeAction.call(tournament: @t, catch: oop, judge: @judge,
                            action: :geofence_override, override_in_lake: true, override_in_sask: true)

      oop.reload
      assert_not_includes oop.flags, "out_of_province", "geofence flag should clear"
      assert_includes oop.flags, "imported_photo", "anti-cheat import flag must survive recompute_flags!"
    end

    test "correct_location preserves the imported_photo flag while clearing geofence flags" do
      oop = create(:catch, user: @user, species: @walleye, length_inches: 25,
                           latitude: 49.9, longitude: -97.1, status: :needs_review,
                           flags: ["out_of_province", "out_of_bounds", "imported_photo"])

      ApplyJudgeAction.call(tournament: @t, catch: oop, judge: @judge,
                            action: :correct_location, latitude: "49.41", longitude: "-103.62")

      oop.reload
      assert_not_includes oop.flags, "out_of_province", "geofence flag should clear"
      assert_includes oop.flags, "imported_photo", "anti-cheat import flag must survive recompute_flags!"
    end

    test "clearing a geofence override drops the catch back out of slots" do
      oop = create(:catch, user: @user, species: @walleye, length_inches: 25,
                           latitude: 49.9, longitude: -97.1, status: :needs_review,
                           override_in_lake: true, override_in_sask: true)
      Catches::PlaceInSlots.call(catch: oop)
      assert_equal 1, oop.catch_placements.active.count

      ApplyJudgeAction.call(tournament: @t, catch: oop, judge: @judge,
                            action: :geofence_override, override_in_lake: false, override_in_sask: false)
      assert_equal 0, oop.reload.catch_placements.active.count
    end

    test "snapshot records location and override state" do
      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge,
                            action: :geofence_override, override_in_lake: true, override_in_sask: false)
      ja = JudgeAction.last
      assert_equal true,  ja.after_state["override_in_lake"]
      assert_equal false, ja.after_state["override_in_sask"]
      assert ja.before_state.key?("latitude"), "snapshot should carry a latitude key"
    end

    # --- correct_location action ----------------------------------------------

    test "correct_location moves a catch into the lake, places it, and clears flags" do
      oop = create(:catch, user: @user, species: @walleye, length_inches: 25,
                           latitude: 49.9, longitude: -97.1, status: :needs_review, # outside SK + lake
                           flags: ["out_of_province", "out_of_bounds"])
      Catches::PlaceInSlots.call(catch: oop)
      assert_equal 0, oop.catch_placements.active.count

      ApplyJudgeAction.call(tournament: @t, catch: oop, judge: @judge,
                            action: :correct_location, latitude: "49.41", longitude: "-103.62") # inside lake + SK

      oop.reload
      assert_in_delta 49.41, oop.latitude.to_f, 0.001
      assert_in_delta(-103.62, oop.longitude.to_f, 0.001)
      assert_equal 1, oop.catch_placements.active.count
      assert_not_includes oop.flags, "out_of_bounds"
      assert_not_includes oop.flags, "out_of_province"
      assert_equal "correct_location", JudgeAction.last.action
    end

    # --- reinstate action -------------------------------------------------------

    test "reinstate restores pre-DQ status and re-places, bumping the promoted backup" do
      backup = create(:catch, user: @user, species: @walleye, length_inches: 12, status: :synced)
      Catches::PlaceInSlots.call(catch: backup)
      assert_equal @catch.id, @entry.catch_placements.active.first&.catch_id, "20 holds the slot"

      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :disqualify, note: "bad photo")
      assert_equal backup.id, @entry.catch_placements.active.first&.catch_id, "backup promoted after DQ"

      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :reinstate)

      @catch.reload
      assert @catch.needs_review?, "status restored to its pre-DQ value"
      assert_equal @catch.id, @entry.catch_placements.active.first&.catch_id, "reinstated 20 reclaims the slot"
      assert_equal "reinstate", JudgeAction.last.action
    end

    test "reinstate notifies the catch owner" do
      ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :disqualify, note: "dq")
      pushes = capture_pushes do
        ApplyJudgeAction.call(tournament: @t, catch: @catch, judge: @judge, action: :reinstate)
      end
      owner = pushes.find { |p| p[:user_id] == @user.id }
      assert owner, "expected a push to the catch owner"
      assert_match(/reinstat/i, owner[:body])
    end
  end
end
