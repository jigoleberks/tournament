require "test_helper"

module Leaderboards
  class BuildBingoTest < ActiveSupport::TestCase
    test "bingo build returns one ranked row per entry with a result" do
      club = Club.create!(name: "C")
      walleye = Species.find_or_create_by!(name: "Walleye")
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
  end
end
