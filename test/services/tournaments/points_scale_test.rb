require "test_helper"

module Tournaments
  class PointsScaleTest < ActiveSupport::TestCase
    test "returns nil for fewer than 3 anglers" do
      [0, 1, 2].each do |n|
        assert_nil PointsScale.call(angler_count: n), "expected nil for #{n} anglers"
      end
    end

    test "returns [3,2,1] for 3 to 9 anglers" do
      [3, 4, 9].each do |n|
        assert_equal [3, 2, 1], PointsScale.call(angler_count: n), "expected [3,2,1] for #{n} anglers"
      end
    end

    test "returns [6,4,2] for 10 to 19 anglers" do
      [10, 15, 19].each do |n|
        assert_equal [6, 4, 2], PointsScale.call(angler_count: n), "expected [6,4,2] for #{n} anglers"
      end
    end

    test "returns [9,6,3] for 20 or more anglers" do
      [20, 50, 100].each do |n|
        assert_equal [9, 6, 3], PointsScale.call(angler_count: n), "expected [9,6,3] for #{n} anglers"
      end
    end
  end
end
