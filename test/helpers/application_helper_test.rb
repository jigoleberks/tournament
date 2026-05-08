require "test_helper"
require "ostruct"

class ApplicationHelperTest < ActionView::TestCase
  setup { travel_to Time.zone.local(2026, 6, 15, 12, 0) }
  teardown { travel_back }

  def tournament(starts_at:, ends_at: nil)
    OpenStruct.new(starts_at: starts_at, ends_at: ends_at)
  end

  test "returns nil when starts_at is missing" do
    assert_nil tournament_window(tournament(starts_at: nil))
  end

  test "no ends_at — renders the start moment" do
    starts = Time.zone.local(2026, 9, 20, 8, 0)
    assert_equal "Sep 20 · 8:00 AM", tournament_window(tournament(starts_at: starts))
  end

  test "same-day window collapses to one date with two times" do
    starts = Time.zone.local(2026, 9, 20, 8, 0)
    ends   = Time.zone.local(2026, 9, 20, 17, 0)
    assert_equal "Sep 20 · 8:00 AM – 5:00 PM",
                 tournament_window(tournament(starts_at: starts, ends_at: ends))
  end

  test "multi-day window shows both moments separately" do
    starts = Time.zone.local(2026, 9, 20, 8, 0)
    ends   = Time.zone.local(2026, 9, 22, 17, 0)
    assert_equal "Sep 20 · 8:00 AM – Sep 22 · 5:00 PM",
                 tournament_window(tournament(starts_at: starts, ends_at: ends))
  end

  test "prior year includes the year in the date" do
    starts = Time.zone.local(2025, 9, 20, 8, 0)
    assert_equal "Sep 20, 2025 · 8:00 AM", tournament_window(tournament(starts_at: starts))
  end

  # Regression for the %l → %-l fix. %l is blank-padded ("  8:00 AM"); %-l is
  # not. Without %-l, the rendered string ends up with a double space which
  # the previous .squeeze(" ") was working around.
  test "uses unpadded hour format — no double spaces" do
    starts = Time.zone.local(2026, 9, 20, 8, 0)
    output = tournament_window(tournament(starts_at: starts))
    assert_not_includes output, "  ", "should not contain double spaces"
  end
end
