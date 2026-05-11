require "test_helper"

module Leaderboards
  module Rankers
    class FishTrainTest < ActiveSupport::TestCase
      Entry = Struct.new(:id, :display_name)

      def entry_row(entry_id:, catches: [])
        # `catches` is an array of [catch_id, length, captured_at_device], ordered by slot_index ascending.
        fish = catches.map do |id, length, captured|
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

      test "ranks by total score descending" do
        a = entry_row(entry_id: 1, catches: [[101, 10, 1.hour.ago], [102, 12, 30.minutes.ago], [103, 8, 20.minutes.ago]])  # 30
        b = entry_row(entry_id: 2, catches: [[201, 8, 50.minutes.ago],  [202, 10, 25.minutes.ago], [203, 7, 15.minutes.ago]]) # 25

        result = FishTrain.call([a, b])

        assert_equal [1, 2], result.map { |r| r[:entry].id }
      end

      test "cars-completed beats fewer-cars at the same total score" do
        # Both total to 30. A has 5 cars, B has 3 cars. A should rank above B.
        a = entry_row(entry_id: 1, catches: [
          [101, 6, 1.hour.ago], [102, 6, 50.minutes.ago],
          [103, 6, 40.minutes.ago], [104, 6, 30.minutes.ago],
          [105, 6, 20.minutes.ago]
        ])
        b = entry_row(entry_id: 2, catches: [
          [201, 10, 55.minutes.ago], [202, 10, 35.minutes.ago],
          [203, 10, 15.minutes.ago]
        ])

        result = FishTrain.call([a, b])

        assert_equal [1, 2], result.map { |r| r[:entry].id }, "5-car 30 should beat 3-car 30"
      end

      test "tie on total + cars-completed broken by largest-fish cascade" do
        # Both total 30, both 3 cars. A has biggest 14, B has biggest 12.
        a = entry_row(entry_id: 1, catches: [[101, 14, 1.hour.ago], [102, 8, 30.minutes.ago], [103, 8, 20.minutes.ago]])
        b = entry_row(entry_id: 2, catches: [[201, 12, 1.hour.ago], [202, 10, 30.minutes.ago], [203, 8, 20.minutes.ago]])

        result = FishTrain.call([a, b])

        assert_equal [1, 2], result.map { |r| r[:entry].id }
      end

      test "ties on total + cars + lengths broken by earliest captured_at_device" do
        a = entry_row(entry_id: 1, catches: [[101, 12, 2.hours.ago], [102, 10, 1.hour.ago], [103, 8, 30.minutes.ago]])
        b = entry_row(entry_id: 2, catches: [[201, 12, 1.hour.ago],  [202, 10, 30.minutes.ago], [203, 8, 20.minutes.ago]])

        result = FishTrain.call([a, b])

        assert_equal [1, 2], result.map { |r| r[:entry].id }, "earlier earliest-catch wins"
      end

      test "final tiebreak by entry.id ascending" do
        same_time = 1.hour.ago
        a = entry_row(entry_id: 7, catches: [[101, 12, same_time], [102, 10, same_time], [103, 8, same_time]])
        b = entry_row(entry_id: 3, catches: [[201, 12, same_time], [202, 10, same_time], [203, 8, same_time]])

        result = FishTrain.call([a, b])

        assert_equal [3, 7], result.map { |r| r[:entry].id }
      end

      test "zero-car entries sort last" do
        empty = entry_row(entry_id: 1, catches: [])
        any   = entry_row(entry_id: 2, catches: [[201, 5, 1.hour.ago], [202, 5, 30.minutes.ago], [203, 5, 20.minutes.ago]])

        result = FishTrain.call([empty, any])

        assert_equal [2, 1], result.map { |r| r[:entry].id }
      end
    end
  end
end
