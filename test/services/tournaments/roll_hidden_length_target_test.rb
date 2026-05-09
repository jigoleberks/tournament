require "test_helper"

module Tournaments
  class RollHiddenLengthTargetTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @t = build(:tournament, club: @club, format: :hidden_length, mode: :solo,
                 kind: :event, starts_at: 2.hours.ago, ends_at: 1.minute.ago)
      @t.scoring_slots.build(species: @walleye, slot_count: 1)
      @t.save!
    end

    test "rolls a target on the quarter inch in [12.00, 22.00]" do
      result = RollHiddenLengthTarget.call(tournament: @t)
      target = @t.reload.hidden_length_target

      assert_not_nil target
      assert_equal target, result[:target]
      assert_equal false, result[:already_rolled]
      assert target >= BigDecimal("12.00")
      assert target <= BigDecimal("22.00")
      assert_equal (target * 4), (target * 4).truncate, "expected quarter-inch step"
    end

    test "is idempotent: second call leaves the target unchanged" do
      RollHiddenLengthTarget.call(tournament: @t)
      first = @t.reload.hidden_length_target

      result = RollHiddenLengthTarget.call(tournament: @t)
      assert_equal true, result[:already_rolled]
      assert_equal first, result[:target]
      assert_equal first, @t.reload.hidden_length_target
    end

  end
end
