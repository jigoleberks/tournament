require "test_helper"

module Catches
  class PlaceInSlotsBingoTest < ActiveSupport::TestCase
    test "a bingo catch creates no placements but flags the tournament affected" do
      club = Club.create!(name: "C")
      walleye, = create_bingo_species!
      t = Tournament.new(club: club, name: "B", mode: :solo, format: :bingo,
                         starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
      t.save!
      u = User.create!(name: "A", email: "a@example.com")
      e = t.tournament_entries.create!
      e.tournament_entry_members.create!(user: u)

      c = create(:catch, user: u, species: walleye, length_inches: 15, captured_at_device: 1.hour.ago)

      result = Catches::PlaceInSlots.call(catch: c, broadcast: false)

      assert_equal 0, CatchPlacement.where(catch_id: c.id).count
      assert_includes result[:affected_tournaments].map(&:id), t.id
    end
  end
end
