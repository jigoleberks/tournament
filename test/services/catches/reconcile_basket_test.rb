require "test_helper"

module Catches
  # ReconcileBasket is the single source of the format->reconciler mapping
  # (see the class comment). This pins the dispatch for formats that keep
  # every catch and therefore never need a re-derive.
  class ReconcileBasketTest < ActiveSupport::TestCase
    test "beat_the_average is a no-op reconcile (every catch kept)" do
      club = create(:club)
      user = create(:user, club: club)
      sp = create(:species, club: club, name: "Walleye")
      t = build(:tournament, club: club, format: :beat_the_average,
                starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      t.scoring_slots.build(species: sp, slot_count: 1)
      t.save!
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: user)

      # Two catches for a single-slot species: Standard's re-derive would keep
      # only the largest, but beat_the_average keeps every catch — both must
      # stay active across the reconcile.
      c1 = create(:catch, user: user, species: sp, length_inches: 20, captured_at_device: 40.minutes.ago)
      c2 = create(:catch, user: user, species: sp, length_inches: 16, captured_at_device: 30.minutes.ago)
      [ c1, c2 ].each { |c| Catches::PlaceInSlots.call(catch: c, broadcast: false) }
      assert_equal 2, entry.catch_placements.active.count, "beat_the_average keeps every catch"

      assert_nil Catches::ReconcileBasket.call(tournament: t, entry: entry, species: sp)

      assert_equal 2, entry.catch_placements.active.count, "reconcile must not drop any catch"
    end
  end
end
