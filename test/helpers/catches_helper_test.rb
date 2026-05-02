require "test_helper"

class CatchesHelperTest < ActionView::TestCase
  # next_range(day, current_start, current_end) → [target_start, target_end]
  # Encodes the tap-rule table from the spec.

  def call(day, current_start, current_end)
    next_range(day, current_start, current_end)
  end

  test "no current selection — tap selects single day" do
    assert_equal [Date.new(2026, 5, 5), Date.new(2026, 5, 5)],
                 call(Date.new(2026, 5, 5), nil, nil)
  end

  test "single day, tap same day — no change" do
    s = Date.new(2026, 5, 5)
    assert_equal [s, s], call(s, s, s)
  end

  test "single day, tap a later day — extends to range" do
    s = Date.new(2026, 5, 5)
    d = Date.new(2026, 5, 12)
    assert_equal [s, d], call(d, s, s)
  end

  test "single day, tap an earlier day — extends backward" do
    s = Date.new(2026, 5, 12)
    d = Date.new(2026, 5, 5)
    assert_equal [d, s], call(d, s, s)
  end

  test "existing range, tap any day — resets to single day on tapped" do
    s = Date.new(2026, 5, 5)
    e = Date.new(2026, 5, 12)
    d = Date.new(2026, 5, 20)
    assert_equal [d, d], call(d, s, e)
  end

  test "existing range, tap inside the range — also resets to single day" do
    s = Date.new(2026, 5, 5)
    e = Date.new(2026, 5, 12)
    d = Date.new(2026, 5, 8)
    assert_equal [d, d], call(d, s, e)
  end
end
