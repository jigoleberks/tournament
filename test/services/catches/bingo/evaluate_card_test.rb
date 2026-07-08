require "test_helper"

module Catches
  module Bingo
    class EvaluateCardTest < ActiveSupport::TestCase
      Lite = Catches::Bingo::EvaluateCard::CatchLite

      def walleye = Species.find_or_create_by!(name: "Walleye")
      def perch = Species.find_or_create_by!(name: "Perch")

      # A tournament with a deterministic layout: put a handful of known tasks in
      # the top row (indices 0-4) so we can assert a completed line.
      def tournament_with_top_row(keys)
        club = Club.create!(name: "C")
        t = Tournament.new(club: club, name: "B", mode: :solo, format: :bingo,
                           starts_at: 3.hours.ago, ends_at: 1.hour.from_now)
        t.save!(validate: false)
        remaining = Catches::Bingo::Tasks.keys - keys
        layout = keys + remaining.first(24 - keys.size)
        layout.insert(12, "free")
        t.update_column(:bingo_layout, layout)
        t
      end

      test "free cell is pre-filled at starts_at; empty card has 1 square, 0 lines" do
        t = tournament_with_top_row(%w[walleye_1 walleye_2 walleye_3 perch_1])
        r = EvaluateCard.call(tournament: t, entry: nil, catches: [])
        assert_equal 1, r.squares_count
        assert_equal 0, r.lines_count
        assert_equal false, r.blackout
        assert_equal t.starts_at, r.cells[12][:completed_at]
      end

      test "one fish fills multiple squares at once" do
        # 16" walleye at 6:30 PM local as 2nd walleye ticks walleye_1/2, band, time, species+length.
        t = tournament_with_top_row(%w[walleye_1 walleye_2 len_1525_1775 walleye_13_185])
        w = walleye.id
        base = Time.utc(2026, 7, 6, 0, 0) # midnight UTC = 6:00 PM CST (America/Regina, no DST)
        cats = [Lite.new(id: 1, length: 15, species_id: w, at: base + 10.minutes),
                Lite.new(id: 2, length: 16, species_id: w, at: base + 30.minutes)]
        r = Time.use_zone("America/Regina") { EvaluateCard.call(tournament: t, entry: nil, catches: cats) }
        keys_filled = r.cells.select { |c| c[:filled] }.map { |c| c[:key] }
        assert_includes keys_filled, "walleye_1"
        assert_includes keys_filled, "walleye_2"
        assert_includes keys_filled, "len_1525_1775"
        assert_includes keys_filled, "walleye_13_185"
        assert_includes keys_filled, "time_hour1" # 6:30 PM local
      end

      test "time-window square fills for a DB-loaded catch in a non-UTC app zone (regression)" do
        # Before the local_hour fix, a DB-read captured_at_device came back as a
        # local TimeWithZone and got re-offset, bucketing a 6:30 PM Saskatchewan
        # catch to noon so the 6-6:59 PM square never filled in production. This
        # exercises the real load_catches path (not injected CatchLite structs).
        Time.use_zone("America/Regina") do
          instant = Time.utc(2026, 7, 6, 0, 30) # 00:30 UTC = 6:30 PM CST (no DST)
          t = tournament_with_top_row(%w[time_hour1 walleye_1 walleye_2 walleye_3])
          t.update_columns(starts_at: instant - 1.hour, ends_at: instant + 1.hour)
          user = User.create!(name: "A", email: "tzdb@example.com")
          entry = t.tournament_entries.create!
          entry.tournament_entry_members.create!(user: user)
          create(:catch, user: user, species: walleye, length_inches: 15, captured_at_device: instant)

          r = EvaluateCard.call(tournament: t, entry: entry)
          keys_filled = r.cells.select { |c| c[:filled] }.map { |c| c[:key] }
          assert_includes keys_filled, "time_hour1",
                          "6:30 PM local catch should fill the 6-6:59 PM square"
        end
      end

      test "an out-of-province catch is excluded from the card, like every other format" do
        # Mirrors PlaceInSlots#skip_for_out_of_province?: a GPS-tagged catch outside
        # Saskatchewan never scores. The card must not fill from it.
        t = tournament_with_top_row(%w[walleye_1 walleye_2 walleye_3 perch_1])
        user = User.create!(name: "A", email: "geo@example.com")
        entry = t.tournament_entries.create!
        entry.tournament_entry_members.create!(user: user)
        # (0, 0) is far outside the Saskatchewan geofence; no judge override.
        create(:catch, user: user, species: walleye, length_inches: 15,
               captured_at_device: 1.hour.ago, latitude: 0.0, longitude: 0.0)

        r = EvaluateCard.call(tournament: t, entry: entry)
        keys_filled = r.cells.select { |c| c[:filled] }.map { |c| c[:key] }
        assert_equal 1, r.squares_count, "only the free square should remain"
        refute_includes keys_filled, "walleye_1"
      end

      test "a completed top row counts as one line with time = max cell time" do
        t = tournament_with_top_row(%w[walleye_1 walleye_2 walleye_3 perch_1 perch_2])
        w = walleye.id; p = perch.id
        base = Time.utc(2026, 7, 6, 1, 0)
        cats = [
          Lite.new(id: 1, length: 15, species_id: w, at: base + 1.minute),
          Lite.new(id: 2, length: 15, species_id: w, at: base + 2.minutes),
          Lite.new(id: 3, length: 15, species_id: w, at: base + 3.minutes),
          Lite.new(id: 4, length: 9,  species_id: p, at: base + 4.minutes),
          Lite.new(id: 5, length: 9,  species_id: p, at: base + 5.minutes),
        ]
        r = EvaluateCard.call(tournament: t, entry: nil, catches: cats)
        assert_equal 1, r.lines_count
        assert_equal base + 5.minutes, r.line_times.first
      end
    end
  end
end
