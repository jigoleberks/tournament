require "test_helper"

module RandomBag
  class AssignTargetTest < ActiveSupport::TestCase
    def random_bag_tournament(min: 70, max: 100, started: true)
      t = build(:tournament, format: :random_bag, target_min_inches: min, target_max_inches: max,
                starts_at: started ? 1.hour.ago : 1.hour.from_now, ends_at: 2.hours.from_now)
      t.scoring_slots.build(species: create(:species), slot_count: 1)
      t.save!
      t
    end

    test "assigns a target within range on a quarter-inch step" do
      t = random_bag_tournament
      entry = create(:tournament_entry, tournament: t)
      target = AssignTarget.call(entry: entry, tournament: t)
      assert_not_nil target
      assert_operator target, :>=, BigDecimal("70")
      assert_operator target, :<=, BigDecimal("100")
      assert_equal (target * 4), (target * 4).truncate, "target is a 1/4-inch step"
      assert_equal target, entry.reload.random_bag_target_inches
    end

    test "is idempotent — a second call keeps the first target" do
      t = random_bag_tournament
      entry = create(:tournament_entry, tournament: t)
      first = AssignTarget.call(entry: entry, tournament: t)
      second = AssignTarget.call(entry: entry, tournament: t)
      assert_equal first, second
    end

    test "does nothing before the tournament has started" do
      t = random_bag_tournament(started: false)
      entry = create(:tournament_entry, tournament: t)
      assert_nil AssignTarget.call(entry: entry, tournament: t)
      assert_nil entry.reload.random_bag_target_inches
    end

    test "does not mint a new target once the tournament has ended" do
      t = random_bag_tournament
      t.update_columns(starts_at: 3.hours.ago, ends_at: 1.hour.ago)
      entry = create(:tournament_entry, tournament: t)
      assert_nil AssignTarget.call(entry: entry, tournament: t.reload),
                 "no post-hoc target after the event is over"
      assert_nil entry.reload.random_bag_target_inches
    end

    test "still returns a target assigned during play after the tournament ends" do
      t = random_bag_tournament
      entry = create(:tournament_entry, tournament: t)
      assigned = AssignTarget.call(entry: entry, tournament: t)   # assigned while active
      t.update_columns(starts_at: 3.hours.ago, ends_at: 1.hour.ago)
      assert_equal assigned, AssignTarget.call(entry: entry, tournament: t.reload)
    end

    test "equal min and max always yields that number" do
      t = random_bag_tournament(min: 85, max: 85)
      entry = create(:tournament_entry, tournament: t)
      assert_equal BigDecimal("85"), AssignTarget.call(entry: entry, tournament: t)
    end

    test "no-op for non-random_bag tournaments" do
      t = create(:tournament, format: :standard)
      entry = create(:tournament_entry, tournament: t)
      assert_nil AssignTarget.call(entry: entry, tournament: t)
    end
  end
end
