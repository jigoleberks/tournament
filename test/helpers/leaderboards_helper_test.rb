require "test_helper"

class LeaderboardsHelperTest < ActionView::TestCase
  include LengthHelper

  FakeT = Struct.new(:fmt) do
    def format_beat_the_average? = fmt == :bta
    def format_hidden_length? = false
    def format_tagged? = false
    def format_progressive_length? = false
    def format_biggest_vs_smallest? = false
    def hidden_length_target = nil
  end

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

  test "bingo format shows lines and squares progress" do
    t = build(:tournament, format: :bingo)
    assert_equal "2 lines · 14/25 squares",
                 leaderboard_score_label({ blackout: false, lines_count: 2, squares_count: 14 }, t)
    assert_equal "1 line · 6/25 squares",
                 leaderboard_score_label({ blackout: false, lines_count: 1, squares_count: 6 }, t)
  end

  test "bingo blackout shows Blackout, free-only shows an em dash" do
    t = build(:tournament, format: :bingo)
    assert_equal "Blackout", leaderboard_score_label({ blackout: true, lines_count: 12, squares_count: 25 }, t)
    assert_equal "—", leaderboard_score_label({ blackout: false, lines_count: 0, squares_count: 1 }, t)
  end

  test "bingo_progress_label formats the shared lines/squares fragment" do
    assert_equal "2 lines · 14/25 squares", bingo_progress_label(lines_count: 2, squares_count: 14)
    assert_equal "1 line · 6/25 squares", bingo_progress_label(lines_count: 1, squares_count: 6)
  end

  test "progressive_length score parts carry up-sizes, not a length" do
    t = build(:tournament, format: :progressive_length)
    row = { total: 3, fish: [], complete: false }
    assert_equal({ up_sizes: 3 }, leaderboard_score_parts(row, t))
  end

  test "progressive_length score label pluralizes up-sizes" do
    t = build(:tournament, format: :progressive_length)
    assert_equal "1 up-size", leaderboard_score_label({ total: 1, fish: [], complete: false }, t)
    assert_equal "3 up-sizes", leaderboard_score_label({ total: 3, fish: [], complete: false }, t)
  end

  test "progressive_length with zero up-sizes has no score" do
    t = build(:tournament, format: :progressive_length)
    assert_nil leaderboard_score_parts({ total: 0, fish: [], complete: false }, t)
  end

  test "beat_the_average revealed row shows distance as off and cm from the shown inches" do
    row = { total: BigDecimal("20"), fish: [{ length_inches: BigDecimal("20"), length_unit: "inches" }],
            distance: BigDecimal("2.17"), complete: false }
    parts = leaderboard_score_parts(row, FakeT.new(:bta))
    assert_equal BigDecimal("2.17"), parts[:off]
    assert_in_delta 20 * 2.54, parts[:cm], 0.001
  end

  test "beat_the_average during-play row has no off" do
    row = { total: BigDecimal("15"), fish: [{ length_inches: BigDecimal("10"), length_unit: "inches" },
                                            { length_inches: BigDecimal("20"), length_unit: "inches" }],
            complete: false }
    parts = leaderboard_score_parts(row, FakeT.new(:bta))
    assert_nil parts[:off]
    assert_in_delta 15 * 2.54, parts[:cm], 0.001   # cm from the avg, NOT summed fish
  end
end
