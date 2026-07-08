require "test_helper"

module Catches
  module Bingo
    class TasksTest < ActiveSupport::TestCase
      # Minimal stand-in for the engine Context.
      Ctx = Struct.new(:catches, :species_map, :zone, keyword_init: true) do
        def species_id(sym) = species_map[sym]
        def local_hour(at) = at.in_time_zone(zone || "UTC").hour
      end
      Fish = Struct.new(:length, :species_id, :at, keyword_init: true)

      def ctx(fish, species_map: { walleye: 1, perch: 2, pike: 3 })
        Ctx.new(catches: fish.sort_by(&:at), species_map: species_map)
      end

      def completed(key, ctx)
        Catches::Bingo::Tasks.fetch(key)[:completed_at].call(ctx)
      end

      test "catalog has exactly 24 unique keys and 24 non-free layout cells" do
        assert_equal 24, Catches::Bingo::Tasks.keys.size
        assert_equal 24, Catches::Bingo::Tasks.keys.uniq.size
        layout = Catches::Bingo::Tasks.random_layout
        assert_equal 25, layout.size
        assert_equal "free", layout[12]
        assert_equal Catches::Bingo::Tasks.keys.sort, (layout - ["free"]).sort
      end

      test "nth-species completes at the Nth matching catch time" do
        t1 = Time.utc(2026, 7, 5, 0, 10)
        t2 = Time.utc(2026, 7, 5, 0, 20)
        c = ctx([Fish.new(length: 15, species_id: 1, at: t1),
                 Fish.new(length: 16, species_id: 1, at: t2)])
        assert_equal t1, completed("walleye_1", c)
        assert_equal t2, completed("walleye_2", c)
        assert_nil completed("walleye_3", c)
      end

      test "any-species length band respects exact bounds and gaps" do
        t = Time.utc(2026, 7, 5, 0, 10)
        assert_equal t, completed("len_1225_1475", ctx([Fish.new(length: 12.25, species_id: 3, at: t)]))
        # 12.0 falls in the gap below the band -> unfilled
        assert_nil completed("len_1225_1475", ctx([Fish.new(length: 12.0, species_id: 3, at: t)]))
      end

      test "species+length uses strict/inclusive bounds as specified" do
        t = Time.utc(2026, 7, 5, 0, 10)
        assert_equal t, completed("walleye_gt19", ctx([Fish.new(length: 19.25, species_id: 1, at: t)]))
        assert_nil completed("walleye_gt19", ctx([Fish.new(length: 19.0, species_id: 1, at: t)])) # strict >
        assert_equal t, completed("walleye_13_185", ctx([Fish.new(length: 18.5, species_id: 1, at: t)])) # inclusive
      end

      test "time window buckets by local hour" do
        t = Time.utc(2026, 7, 5, 19, 30) # hour 19 -> hour2
        assert_nil completed("time_hour1", ctx([Fish.new(length: 10, species_id: 1, at: t)]))
        assert_equal t, completed("time_hour2", ctx([Fish.new(length: 10, species_id: 1, at: t)]))
      end

      test "two_within_10min completes at the 2nd fish of the first close pair" do
        a = Time.utc(2026, 7, 5, 0, 0)
        b = Time.utc(2026, 7, 5, 0, 9)  # 9 min after a -> pair
        c = ctx([Fish.new(length: 10, species_id: 1, at: a), Fish.new(length: 10, species_id: 1, at: b)])
        assert_equal b, completed("two_within_10min", c)
        far = ctx([Fish.new(length: 10, species_id: 1, at: a),
                   Fish.new(length: 10, species_id: 1, at: a + 11.minutes)])
        assert_nil completed("two_within_10min", far)
      end

      test "over_10_fish completes at the 11th catch" do
        base = Time.utc(2026, 7, 5, 0, 0)
        fish = (0...10).map { |i| Fish.new(length: 10, species_id: 1, at: base + i.minutes) }
        assert_nil completed("over_10_fish", ctx(fish))
        eleven = fish + [Fish.new(length: 10, species_id: 1, at: base + 10.minutes)]
        assert_equal base + 10.minutes, completed("over_10_fish", ctx(eleven))
      end

      test "species task is unfillable when species id is absent" do
        t = Time.utc(2026, 7, 5, 0, 10)
        c = ctx([Fish.new(length: 15, species_id: 99, at: t)], species_map: { walleye: nil })
        assert_nil completed("walleye_1", c)
      end
    end
  end
end
