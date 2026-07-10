require "test_helper"

module Catches
  # Guards the finding that each basket format's rules live in TWO places: the
  # incremental branch in PlaceInSlots (applied per new catch) and the
  # whole-basket re-derive in the matching Reconcile* class. They must agree, or
  # a judge length-edit reconcile would produce a different basket than live
  # placement did. This pins them together: place a set of catches incrementally,
  # then reconcile the same set and assert the resulting basket is identical.
  #
  # The comparison is by catch IDENTITY, not just the length multiset: on an
  # equal-length tie the two paths can keep the same lengths but a different
  # physical catch, which silently changes the credited photo and the entry's
  # earliest_catch_at (a leaderboard tiebreaker). Comparing ids catches that.
  class PlaceReconcileConsistencyTest < ActiveSupport::TestCase
    RECONCILERS = {
      standard: ReconcileStandard,
      smallest_fish: ReconcileSmallestFish,
      pro_walleye: ReconcileProWalleye,
      biggest_vs_smallest: ReconcileBvsExtremes,
      # Progressive Length has no separate incremental branch — PlaceInSlots calls
      # the reconciler directly — so this pairing is true by construction. It stays
      # in the map so the generative fuzz test below covers the format, and so
      # anyone who later reintroduces an incremental branch is caught immediately.
      progressive_length: ReconcileProgressiveLength,
    }.freeze

    # Places each length incrementally, then reconciles the same eligible set.
    # captured_at defaults to increasing with placement order (capture order ==
    # placement order); pass capture_offsets (minutes-ago per placement index) to
    # decouple them and exercise the offline-sync case where a later-placed catch
    # was captured earlier.
    def basket_for(format:, lengths:, capture_offsets: nil)
      club = create(:club)
      # find_or_create so a single test can call basket_for repeatedly (the fuzz
      # test) without tripping Species' global name-uniqueness validation.
      walleye = Species.find_or_create_by!(name: "Walleye")
      user = create(:user, club: club)
      t = build(:tournament, club: club, format: format, mode: :team,
                starts_at: 2.hours.ago, ends_at: 1.hour.from_now)
      t.scoring_slots.build(species: walleye, slot_count: 5)
      t.save!
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: user)

      lengths.each_with_index do |len, i|
        minutes = capture_offsets ? capture_offsets[i] : (90 - i)
        c = create(:catch, user: user, species: walleye, length_inches: len,
                           captured_at_device: minutes.minutes.ago, status: :synced)
        PlaceInSlots.call(catch: c)
      end
      incremental = active_catch_ids(entry)

      RECONCILERS.fetch(format).call(tournament: t, entry: entry, species: walleye)
      reconciled = active_catch_ids(entry)

      [incremental, reconciled]
    end

    # The set of active catches, by identity — sorted so slot_index differences
    # (reconcile renumbers 0..n; incremental keeps original slots) don't matter.
    def active_catch_ids(entry)
      entry.catch_placements.where(active: true).pluck(:catch_id).sort
    end

    def assert_consistent(format:, lengths:, capture_offsets: nil)
      incremental, reconciled = basket_for(format: format, lengths: lengths, capture_offsets: capture_offsets)
      assert_equal incremental, reconciled,
                   "PlaceInSlots and #{RECONCILERS.fetch(format)} kept different catches for #{lengths.inspect}"
    end

    # length_inches: 15-21 are ≤55cm ("under"); 22+ are >55cm ("over").
    PRO_WALLEYE_CASES = [
      [16, 17, 18, 19, 20, 21],             # unders overflow the 5-fish basket
      [24, 26, 28],                         # overs exceed the 2-over cap
      [16, 17, 18, 24, 26, 28, 30],         # mix: 3 overs (cap 2) + 4 unders
      [30, 28, 26, 24, 18, 17, 16],         # same set, reverse order
      [20, 20, 20, 20, 20, 20],             # all-equal unders (tie handling)
      [18, 18, 19, 20, 21, 22],             # tied unders bumped by an over — tie identity
      [26, 24, 28, 16, 18, 17, 19, 20, 21], # larger scrambled mix
    ].freeze

    PRO_WALLEYE_CASES.each_with_index do |lengths, i|
      test "pro_walleye incremental placement matches reconcile ##{i} #{lengths.inspect}" do
        assert_consistent(format: :pro_walleye, lengths: lengths)
      end
    end

    SMALLEST_FISH_CASES = [
      [16, 17, 18, 19, 20, 21],             # more catches than slots -> keep 5 smallest
      [21, 20, 19, 18, 17, 16],             # same set, reverse order
      [18, 18, 18, 18, 18, 18],             # all-equal (tie handling)
      [20, 20, 19, 18, 17, 16],             # tied largest bumped — tie identity
      [22, 15, 19, 16, 24, 17, 30],         # scrambled mix
    ].freeze

    SMALLEST_FISH_CASES.each_with_index do |lengths, i|
      test "smallest_fish incremental placement matches reconcile ##{i} #{lengths.inspect}" do
        assert_consistent(format: :smallest_fish, lengths: lengths)
      end
    end

    STANDARD_CASES = [
      [16, 17, 18, 19, 20, 21],             # more catches than slots -> keep 5 largest
      [21, 20, 19, 18, 17, 16],             # same set, reverse order
      [20, 20, 20, 20, 20, 20],             # all-equal (tie handling)
      [18, 18, 19, 20, 21, 22],             # tied smallest bumped — tie identity
      [17, 22, 15, 19, 30, 16, 24],         # scrambled mix
    ].freeze

    STANDARD_CASES.each_with_index do |lengths, i|
      test "standard incremental placement matches reconcile ##{i} #{lengths.inspect}" do
        assert_consistent(format: :standard, lengths: lengths)
      end
    end

    BIGGEST_VS_SMALLEST_CASES = [
      [16, 20, 18, 14, 22],                 # extremes shift as bigger/smaller arrive
      [22, 14, 18, 20, 16],                 # same set, different order
      [20, 20, 18],                         # tied biggest — which 20 is kept
      [18, 20, 20],                         # tied biggest, later placement
      [20, 20, 25],                         # tied pair, then a strictly BIGGER catch
      [14, 14, 8],                          # tied pair, then a strictly SMALLER catch
    ].freeze

    BIGGEST_VS_SMALLEST_CASES.each_with_index do |lengths, i|
      test "biggest_vs_smallest incremental placement matches reconcile ##{i} #{lengths.inspect}" do
        assert_consistent(format: :biggest_vs_smallest, lengths: lengths)
      end
    end

    # Property test: incremental placement must equal whole-basket reconcile for
    # MANY random catch sequences, not just the hand-picked cases above. A fixed
    # case list can — and did — miss shapes like BvS "two equal-length extremes,
    # then a strictly more-extreme catch," so the two paths could silently keep
    # different catches while every enumerated case passed. A generative test
    # closes that hole permanently: lengths are drawn from a small pool WITH
    # duplicates so equal-length ties are common, and capture order is shuffled
    # independently of placement order to exercise the earliest-capture tiebreak.
    FUZZ_POOL = [16, 18, 20, 20, 20, 22, 25].freeze # weighted to 20" so ties are frequent

    RECONCILERS.each_key.with_index do |format, idx|
      test "#{format} incremental placement matches reconcile across random sequences" do
        rng = Random.new(1000 + idx) # fixed seed per format -> reproducible
        10.times do
          n = rng.rand(2..6)
          lengths = Array.new(n) { FUZZ_POOL.sample(random: rng) }
          offsets = (1..n).map { |i| 80 + i }.shuffle(random: rng)
          assert_consistent(format: format, lengths: lengths, capture_offsets: offsets)
        end
      end
    end

    # Offline sync: a later-placed catch was captured EARLIER than the incumbents.
    # A full basket of equal-length fish gets one more equal-length catch that was
    # captured before all of them; reconcile keeps the earliest-captured and drops
    # the latest, so incremental placement must displace the latest-captured
    # incumbent rather than no-op on the length tie.
    test "standard matches reconcile when capture order != placement order on a tie" do
      assert_consistent(format: :standard,
                        lengths: [20, 20, 20, 20, 20, 20],
                        capture_offsets: [90, 89, 88, 87, 86, 91])
    end

    test "smallest_fish matches reconcile when capture order != placement order on a tie" do
      assert_consistent(format: :smallest_fish,
                        lengths: [18, 18, 18, 18, 18, 18],
                        capture_offsets: [90, 89, 88, 87, 86, 91])
    end
  end
end
