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

  test "month_calendar_link_url — no current selection, returns URL with start=end=tapped" do
    url = month_calendar_link_url(Date.new(2026, 5, 5),
                                  current_start: nil, current_end: nil,
                                  params: {}, path_helper: :catches_path)
    assert_match %r{\?.*start=2026-05-05}, url
    assert_match %r{\?.*end=2026-05-05}, url
  end

  test "month_calendar_link_url — preserves species and sort params" do
    url = month_calendar_link_url(Date.new(2026, 5, 5),
                                  current_start: nil, current_end: nil,
                                  params: { species: "3", sort: "longest" },
                                  path_helper: :catches_path)
    assert_match "species=3", url
    assert_match "sort=longest", url
    assert_match "start=2026-05-05", url
  end

  test "month_calendar_link_url — single day + later tap encodes range" do
    s = Date.new(2026, 5, 5)
    d = Date.new(2026, 5, 12)
    url = month_calendar_link_url(d,
                                  current_start: s, current_end: s,
                                  params: {}, path_helper: :catches_path)
    assert_match "start=2026-05-05", url
    assert_match "end=2026-05-12", url
  end

  test "month_calendar_link_url — drops controller/action keys from params" do
    url = month_calendar_link_url(Date.new(2026, 5, 5),
                                  current_start: nil, current_end: nil,
                                  params: { controller: "catches", action: "index" },
                                  path_helper: :catches_path)
    refute_match "controller=", url
    refute_match "action=", url
  end
end
