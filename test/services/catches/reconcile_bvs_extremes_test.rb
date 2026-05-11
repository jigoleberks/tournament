require "test_helper"

module Catches
  class ReconcileBvsExtremesTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @user = create(:user, club: @club)
      @t = build(:tournament, club: @club, format: :biggest_vs_smallest, mode: :solo,
                 kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      @t.scoring_slots.build(species: @walleye, slot_count: 1)
      @t.save!
      @entry = create(:tournament_entry, tournament: @t)
      create(:tournament_entry_member, tournament_entry: @entry, user: @user)
    end

    def make_catch(length, captured: 30.minutes.ago, status: :synced, user: @user)
      create(:catch, user: user, species: @walleye, length_inches: length,
                     captured_at_device: captured, status: status)
    end

    test "no eligible catches: clears all active placements and creates none" do
      c = make_catch(18)
      Catches::PlaceInSlots.call(catch: c)
      c.update!(status: :disqualified)

      ReconcileBvsExtremes.call(tournament: @t, entry: @entry, species: @walleye)

      assert_equal 0, @entry.catch_placements.where(active: true).count
    end

    test "one eligible catch: leaves a single active placement at slot 0" do
      c1 = make_catch(18, captured: 40.minutes.ago)
      c2 = make_catch(12, captured: 30.minutes.ago)
      Catches::PlaceInSlots.call(catch: c1)
      Catches::PlaceInSlots.call(catch: c2)
      c2.update!(status: :disqualified)

      ReconcileBvsExtremes.call(tournament: @t, entry: @entry, species: @walleye)

      active = @entry.catch_placements.where(active: true).order(:slot_index).to_a
      assert_equal 1, active.size
      assert_equal 0, active.first.slot_index
      assert_equal c1.id, active.first.catch_id
    end

    test "two or more eligible: places biggest at slot 0 and smallest at slot 1" do
      big    = make_catch(22, captured: 50.minutes.ago)
      mid    = make_catch(16, captured: 40.minutes.ago)
      small  = make_catch(10, captured: 30.minutes.ago)
      [big, mid, small].each { |c| Catches::PlaceInSlots.call(catch: c) }

      # Mid was dropped in the middle; small bumped 10's predecessor. Now DQ the
      # currently-biggest (22) so we have eligible {16, 10}, and call the
      # reconciler explicitly to verify it picks the right pair.
      big.update!(status: :disqualified)

      ReconcileBvsExtremes.call(tournament: @t, entry: @entry, species: @walleye)

      active = @entry.catch_placements.where(active: true).order(:slot_index).to_a
      assert_equal 2, active.size
      assert_equal [0, 1], active.map(&:slot_index)
      assert_equal mid.id,   active[0].catch_id, "biggest of remaining should be at slot 0"
      assert_equal small.id, active[1].catch_id, "smallest of remaining should be at slot 1"
    end

    test "the BvS bug case: DQ'ing the smallest selects the next-smallest, not the next-largest" do
      # Catches: 22, 10, 14, 12. After incremental placement, active is [22, 10]
      # (the two extremes); 14 and 12 were mid-range and dropped. DQ the 10 →
      # eligible set becomes {22, 14, 12}. Correct answer: [22, 12]. Wrong
      # (PromoteBackup-style) answer: [22, 14].
      [22, 10, 14, 12].each_with_index do |len, i|
        Catches::PlaceInSlots.call(catch: make_catch(len, captured: (30 - i).minutes.ago))
      end
      smallest = ::Catch.find_by!(length_inches: 10)
      smallest.update!(status: :disqualified)
      smallest.catch_placements.where(active: true).update_all(active: false)

      ReconcileBvsExtremes.call(tournament: @t, entry: @entry, species: @walleye)

      lens = @entry.catch_placements.where(active: true).includes(:catch).map { |p| p.catch.length_inches.to_f }.sort
      assert_equal [12.0, 22.0], lens,
                   "expected biggest 22 and the actual remaining smallest 12, not the next-largest 14"
    end

    test "ignores catches outside the tournament time window" do
      inside  = make_catch(18, captured: 30.minutes.ago)
      Catches::PlaceInSlots.call(catch: inside)
      pre     = make_catch(22, captured: 2.hours.ago)
      post    = make_catch(8,  captured: 2.hours.from_now)

      ReconcileBvsExtremes.call(tournament: @t, entry: @entry, species: @walleye)

      active = @entry.catch_placements.where(active: true).includes(:catch).to_a
      assert_equal 1, active.size
      assert_equal inside.id, active.first.catch_id
      assert_not ::CatchPlacement.exists?(catch_id: [pre.id, post.id], active: true)
    end

    test "ties at the biggest length resolve to the earliest-captured catch" do
      # Create the earlier-captured 18 FIRST so it has the lower row id. Without a
      # deterministic tiebreaker, the natural query order returns the earlier-id
      # row first and stable-sort puts the later-captured 18 at sorted.last, which
      # would land at slot 0 — opposite of the BvS ranker's "earliest catch wins"
      # tiebreak.
      earlier_big = make_catch(18, captured: 30.minutes.ago)
      _smaller    = make_catch(12, captured: 20.minutes.ago)
      later_big   = make_catch(18, captured: 10.minutes.ago)
      [earlier_big, _smaller, later_big].each { |c| Catches::PlaceInSlots.call(catch: c) }
      @entry.catch_placements.where(active: true).update_all(active: false)

      ReconcileBvsExtremes.call(tournament: @t, entry: @entry, species: @walleye)

      biggest = @entry.catch_placements.where(active: true, slot_index: 0).first
      assert_equal earlier_big.id, biggest.catch_id,
                   "expected the earlier-captured 18\" to win the biggest tiebreak, not the later-captured one"
    end

    test "ties at the smallest length resolve to the earliest-captured catch" do
      # Create the LATER-captured 12 first so it has the lower row id. Without
      # a deterministic tiebreaker, sorted.first picks the later-captured one
      # — opposite of the BvS ranker's "earliest catch wins" tiebreak.
      later_small   = make_catch(12, captured: 10.minutes.ago)
      _bigger       = make_catch(20, captured: 20.minutes.ago)
      earlier_small = make_catch(12, captured: 30.minutes.ago)
      [later_small, _bigger, earlier_small].each { |c| Catches::PlaceInSlots.call(catch: c) }
      @entry.catch_placements.where(active: true).update_all(active: false)

      ReconcileBvsExtremes.call(tournament: @t, entry: @entry, species: @walleye)

      smallest = @entry.catch_placements.where(active: true, slot_index: 1).first
      assert_equal earlier_small.id, smallest.catch_id,
                   "expected the earlier-captured 12\" to win the smallest tiebreak, not the later-captured one"
    end

    test "reuses an existing inactive placement at the target slot for the desired catch" do
      c1 = make_catch(20, captured: 40.minutes.ago)
      c2 = make_catch(12, captured: 30.minutes.ago)
      Catches::PlaceInSlots.call(catch: c1)
      Catches::PlaceInSlots.call(catch: c2)
      # c2's placement is at slot 1. Manually deactivate everything and ensure
      # the reconciler reactivates c2's existing row instead of duplicating it.
      original_c2_pl = c2.catch_placements.where(slot_index: 1).first
      @entry.catch_placements.where(active: true).update_all(active: false)

      assert_no_difference -> { ::CatchPlacement.where(catch_id: c2.id).count } do
        ReconcileBvsExtremes.call(tournament: @t, entry: @entry, species: @walleye)
      end
      assert original_c2_pl.reload.active?, "expected the original c2 placement row to be reactivated"
    end
  end
end
