require "test_helper"

module Leaderboards
  module Rankers
    class HiddenLengthTest < ActiveSupport::TestCase
      Entry = Struct.new(:id, :display_name)
      FakeTournament = Struct.new(:hidden_length_target) do
        def format_hidden_length? = true
      end

      def entry_row(entry_id:, catches: [])
        # `catches` is an array of [catch_id, length, captured_at_device]
        fish = catches.sort_by { |c| -c[1] }.map do |id, length, captured|
          {
            id: id,
            length_inches: length,
            captured_at_device: captured,
            species_name: "Walleye",
            angler_name: "Angler #{entry_id}",
            logged_by_name: nil,
            approver_name: nil
          }
        end
        {
          entry: Entry.new(entry_id, "Entry #{entry_id}"),
          total: fish.sum { |f| f[:length_inches] },
          fish: fish,
          fish_lengths: fish.map { |f| f[:length_inches] },
          earliest_catch_at: fish.map { |f| f[:captured_at_device] }.compact.min,
          complete: false
        }
      end

      # ---- pre-reveal mode (target nil) ----

      test "pre-reveal: returns one row per catch sorted by length desc" do
        tournament = FakeTournament.new(nil)
        a = entry_row(entry_id: 1, catches: [[101, 19, 1.hour.ago], [102, 14, 30.minutes.ago]])
        b = entry_row(entry_id: 2, catches: [[201, 22, 45.minutes.ago]])

        result = HiddenLength.call([a, b], tournament: tournament)

        assert_equal [22, 19, 14], result.map { |r| r[:total] }
      end

      test "pre-reveal: same-length ties broken by earliest captured_at_device" do
        tournament = FakeTournament.new(nil)
        earlier = entry_row(entry_id: 1, catches: [[101, 18, 2.hours.ago]])
        later   = entry_row(entry_id: 2, catches: [[201, 18, 30.minutes.ago]])

        result = HiddenLength.call([earlier, later], tournament: tournament)

        assert_equal [1, 2], result.map { |r| r[:entry].id }
      end

      # ---- post-reveal mode (target set) ----

      test "post-reveal: one row per entry, picks the closest catch" do
        tournament = FakeTournament.new(BigDecimal("17.00"))
        a = entry_row(entry_id: 1, catches: [[101, 22, 1.hour.ago], [102, 17.5, 30.minutes.ago]])
        b = entry_row(entry_id: 2, catches: [[201, 14, 45.minutes.ago]])

        result = HiddenLength.call([a, b], tournament: tournament)

        assert_equal 2, result.size
        # A's closest is the 17.5 fish (0.5 off); B's closest is 14 (3.0 off).
        assert_equal [1, 2], result.map { |r| r[:entry].id }
        assert_equal 17.5, result[0][:total]
        assert_equal 14,   result[1][:total]
        assert_equal [102], result[0][:fish].map { |f| f[:id] }
        assert_equal 1, result[0][:fish].size
      end

      test "post-reveal: distance ties broken by earliest catch" do
        tournament = FakeTournament.new(BigDecimal("16.00"))
        # 15.5 (0.5 off, earlier) vs 16.5 (0.5 off, later) → earlier wins
        early = entry_row(entry_id: 1, catches: [[101, 15.5, 2.hours.ago]])
        late  = entry_row(entry_id: 2, catches: [[201, 16.5, 30.minutes.ago]])

        result = HiddenLength.call([early, late], tournament: tournament)

        assert_equal [1, 2], result.map { |r| r[:entry].id }
      end

      test "post-reveal: same-time distance ties broken by entry.id ascending" do
        tournament = FakeTournament.new(BigDecimal("16.00"))
        same_time = 1.hour.ago
        a = entry_row(entry_id: 7, catches: [[101, 15.5, same_time]])
        b = entry_row(entry_id: 3, catches: [[201, 15.5, same_time]])

        result = HiddenLength.call([a, b], tournament: tournament)

        assert_equal [3, 7], result.map { |r| r[:entry].id }
      end

      test "post-reveal: entries with no catches sort last" do
        tournament = FakeTournament.new(BigDecimal("16.00"))
        empty = entry_row(entry_id: 1, catches: [])
        any   = entry_row(entry_id: 2, catches: [[201, 16, 1.hour.ago]])

        result = HiddenLength.call([empty, any], tournament: tournament)

        assert_equal [2, 1], result.map { |r| r[:entry].id }
      end

      test "post-reveal: row :total is the chosen catch length and :fish has just that catch" do
        tournament = FakeTournament.new(BigDecimal("17.00"))
        a = entry_row(entry_id: 1, catches: [[101, 22, 1.hour.ago], [102, 17.5, 30.minutes.ago], [103, 12, 15.minutes.ago]])

        result = HiddenLength.call([a], tournament: tournament)

        assert_equal 1, result.size
        assert_equal 17.5, result.first[:total]
        assert_equal [102], result.first[:fish].map { |f| f[:id] }
      end
    end
  end
end
