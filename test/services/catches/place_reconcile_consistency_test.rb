require "test_helper"

module Catches
  # Guards the finding that each basket format's rules live in TWO places: the
  # incremental branch in PlaceInSlots (applied per new catch) and the
  # whole-basket re-derive in the matching Reconcile* class. They must agree, or
  # a judge length-edit reconcile would produce a different basket than live
  # placement did. This pins them together: place a set of catches incrementally,
  # then reconcile the same set and assert the resulting basket is identical.
  #
  # captured_at increases with placement order so the "first-to-set wins" tiebreak
  # of the incremental branches and the "earliest captured_at" tiebreak of the
  # reconcilers resolve the same way on equal-length ties.
  class PlaceReconcileConsistencyTest < ActiveSupport::TestCase
    def basket_for(format:, lengths:)
      club = create(:club)
      walleye = create(:species, name: "Walleye")
      user = create(:user, club: club)
      t = build(:tournament, club: club, format: format, mode: :team,
                starts_at: 2.hours.ago, ends_at: 1.hour.from_now)
      t.scoring_slots.build(species: walleye, slot_count: 5)
      t.save!
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: user)

      lengths.each_with_index do |len, i|
        c = create(:catch, user: user, species: walleye, length_inches: len,
                           captured_at_device: (90 - i).minutes.ago, status: :synced)
        PlaceInSlots.call(catch: c)
      end
      incremental = active_multiset(entry)

      reconciler = { pro_walleye: ReconcileProWalleye, smallest_fish: ReconcileSmallestFish }.fetch(format)
      reconciler.call(tournament: t, entry: entry, species: walleye)
      reconciled = active_multiset(entry)

      [incremental, reconciled]
    end

    def active_multiset(entry)
      entry.catch_placements.where(active: true).includes(:catch)
           .map { |p| p.catch.length_inches.to_i }.sort
    end

    # length_inches: 15-21 are ≤55cm ("under"); 22+ are >55cm ("over").
    PRO_WALLEYE_CASES = [
      [16, 17, 18, 19, 20, 21],             # unders overflow the 5-fish basket
      [24, 26, 28],                         # overs exceed the 2-over cap
      [16, 17, 18, 24, 26, 28, 30],         # mix: 3 overs (cap 2) + 4 unders
      [30, 28, 26, 24, 18, 17, 16],         # same set, reverse order
      [20, 20, 20, 20, 20, 20],             # all-equal unders (tie handling)
      [26, 24, 28, 16, 18, 17, 19, 20, 21], # larger scrambled mix
    ].freeze

    PRO_WALLEYE_CASES.each_with_index do |lengths, i|
      test "pro_walleye incremental placement matches reconcile ##{i} #{lengths.inspect}" do
        incremental, reconciled = basket_for(format: :pro_walleye, lengths: lengths)
        assert_equal incremental, reconciled,
                     "PlaceInSlots and ReconcileProWalleye disagree for #{lengths.inspect}"
      end
    end

    SMALLEST_FISH_CASES = [
      [16, 17, 18, 19, 20, 21],             # more catches than slots -> keep 5 smallest
      [21, 20, 19, 18, 17, 16],             # same set, reverse order
      [18, 18, 18, 18, 18, 18],             # all-equal (tie handling)
      [22, 15, 19, 16, 24, 17, 30],         # scrambled mix
    ].freeze

    SMALLEST_FISH_CASES.each_with_index do |lengths, i|
      test "smallest_fish incremental placement matches reconcile ##{i} #{lengths.inspect}" do
        incremental, reconciled = basket_for(format: :smallest_fish, lengths: lengths)
        assert_equal incremental, reconciled,
                     "PlaceInSlots and ReconcileSmallestFish disagree for #{lengths.inspect}"
      end
    end
  end
end
