require "test_helper"

module Leaderboards
  class BuildBingoTest < ActiveSupport::TestCase
    test "bingo build returns one ranked row per entry with a result" do
      club = Club.create!(name: "C")
      walleye, = create_bingo_species!
      t = Tournament.new(club: club, name: "B", mode: :solo, format: :bingo,
                         starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
      t.save! # auto-layout

      u1 = User.create!(name: "A", email: "a@example.com")
      u2 = User.create!(name: "B", email: "b@example.com")
      e1 = t.tournament_entries.create!
      e1.tournament_entry_members.create!(user: u1)
      e2 = t.tournament_entries.create!
      e2.tournament_entry_members.create!(user: u2)

      # u1 catches a walleye in window; u2 catches nothing.
      create(:catch, user: u1, species: walleye, length_inches: 15,
             captured_at_device: 1.hour.ago)

      rows = Leaderboards::Build.call(tournament: t)
      assert_equal 2, rows.size
      # u1 has at least the walleye_1 + free squares, so ranks first.
      assert_equal e1.id, rows.first[:entry].id
      assert_operator rows.first[:squares_count], :>=, 2
      assert_equal 1, rows.last[:squares_count] # only free
    end

    test "resolves bingo species a bounded number of times regardless of entry count" do
      club = Club.create!(name: "C")
      create_bingo_species!
      t = Tournament.new(club: club, name: "B", mode: :solo, format: :bingo,
                         starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
      t.save!

      3.times do |i|
        u = User.create!(name: "U#{i}", email: "u#{i}@example.com")
        entry = t.tournament_entries.create!
        entry.tournament_entry_members.create!(user: u)
      end

      # species_id_map resolves all 3 bingo species in a single IN query for the
      # whole build; the count must not scale with the number of entries (the
      # pre-fix N+1 was 3×N, and the pre-batching version was 3 separate queries).
      species_queries = count_queries(/FROM "species"/) do
        Leaderboards::Build.call(tournament: t)
      end
      assert_operator species_queries, :<=, 1
    end

    test "loads every entrant's catches in a single query, not one per entry" do
      club = Club.create!(name: "C")
      walleye, = create_bingo_species!
      t = Tournament.new(club: club, name: "B", mode: :solo, format: :bingo,
                         starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
      t.save!

      3.times do |i|
        u = User.create!(name: "U#{i}", email: "u#{i}@example.com")
        entry = t.tournament_entries.create!
        entry.tournament_entry_members.create!(user: u)
        create(:catch, user: u, species: walleye, length_inches: 16,
               captured_at_device: 1.hour.ago, status: :synced)
      end

      catch_queries = count_queries(/FROM "catches"/) do
        Leaderboards::Build.call(tournament: t)
      end
      assert_equal 1, catch_queries, "expected one batched catches query, not one per entry"
    end
  end
end
