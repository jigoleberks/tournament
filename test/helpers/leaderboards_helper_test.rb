require "test_helper"

class LeaderboardsHelperTest < ActionView::TestCase
  include LengthHelper

  test "standard format shows inches and cm" do
    t = build(:tournament, format: :standard)
    row = { total: 44.0, complete: true,
            fish: [{ length_inches: 24.0, length_unit: "inches" },
                   { length_inches: 20.0, length_unit: "inches" }] }
    label = leaderboard_score_label(row, t)
    assert_includes label, '"'
    assert_includes label, "cm"
  end

  test "tagged format shows a ticket count, pluralized" do
    t = build(:tournament, format: :tagged)
    assert_equal "2 tickets", leaderboard_score_label({ total: 2, fish: [], complete: false }, t)
    assert_equal "1 ticket",  leaderboard_score_label({ total: 1, fish: [], complete: false }, t)
  end

  test "zero non-complete score renders an em dash" do
    t = build(:tournament, format: :standard)
    assert_equal "—", leaderboard_score_label({ total: 0, fish: [], complete: false }, t)
  end

  test "biggest_vs_smallest complete zero is a real score, not a dash" do
    t = build(:tournament, format: :biggest_vs_smallest)
    row = { total: 0, complete: true,
            fish: [{ length_inches: 20.0, length_unit: "inches" },
                   { length_inches: 20.0, length_unit: "inches" }] }
    refute_equal "—", leaderboard_score_label(row, t)
  end
end
