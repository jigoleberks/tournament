require "test_helper"

module RandomBag
  class BestBagTest < ActiveSupport::TestCase
    def fish(*lengths)
      lengths.each_with_index.map { |l, i| { id: i + 1, length_inches: BigDecimal(l.to_s) } }
    end

    test "empty fish -> empty subset, nil sum/distance" do
      r = BestBag.call(fish: [], target: 80)
      assert_equal [], r[:subset]
      assert_nil r[:sum]
      assert_nil r[:distance]
    end

    test "nil target -> empty subset" do
      assert_equal [], BestBag.call(fish: fish(10, 20), target: nil)[:subset]
    end

    test "picks the up-to-5 subset closest to target" do
      # target 80; best five-ish combo. 18+17+16+15+14 = 80 exactly.
      r = BestBag.call(fish: fish(18, 17, 16, 15, 14, 5), target: 80)
      assert_equal BigDecimal("80"), r[:sum]
      assert_equal BigDecimal("0"), r[:distance]
      assert_equal 5, r[:subset].size
    end

    test "never uses more than 5 fish even when more are available" do
      r = BestBag.call(fish: fish(10, 10, 10, 10, 10, 10, 10, 10), target: 80)
      assert_operator r[:subset].size, :<=, 5
      assert_equal BigDecimal("50"), r[:sum]        # best reachable with <=5 tens
      assert_equal BigDecimal("30"), r[:distance]
    end

    test "a single fish can be the best bag" do
      r = BestBag.call(fish: fish(79, 5, 4), target: 80)
      assert_equal 1, r[:subset].size
      assert_equal BigDecimal("79"), r[:sum]
      assert_equal BigDecimal("1"), r[:distance]
    end

    test "over and under are symmetric (absolute distance)" do
      # target 80; 82 (over, dist 2) beats 77 (under, dist 3)
      r = BestBag.call(fish: fish(82, 77), target: 80)
      assert_equal BigDecimal("82"), r[:sum]
      assert_equal BigDecimal("2"), r[:distance]
    end
  end
end
