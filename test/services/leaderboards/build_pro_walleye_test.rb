require "test_helper"

module Leaderboards
  class BuildProWalleyeTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, name: "Walleye")
      @t = build(:tournament, club: @club, format: :pro_walleye, mode: :team,
                 starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      @t.scoring_slots.build(species: @walleye, slot_count: 5)
      @t.save!
    end

    def entry_with(lengths)
      u = create(:user, club: @club)
      e = create(:tournament_entry, tournament: @t)
      create(:tournament_entry_member, tournament_entry: e, user: u)
      lengths.each { |l| Catches::PlaceInSlots.call(catch: create(:catch, user: u, species: @walleye, length_inches: l)) }
      e
    end

    test "ranks by total length and flags a full 5-fish basket complete" do
      big_total = entry_with([21, 20, 19, 26, 24]) # small 60 + big 50 = 110
      small_total = entry_with([18, 17, 22])        # 57
      rows = Build.call(tournament: @t)
      assert_equal big_total.id, rows.first[:entry].id
      assert rows.first[:complete], "5 fish => complete"
      assert_not rows.last[:complete], "3 fish => not complete"
    end

    test "pure total wins: a heavier 4-fish partial outranks a lighter full 5-fish basket" do
      full_lighter  = entry_with([15, 15, 15, 22, 22]) # complete 5 fish, total 89
      partial_heavier = entry_with([21, 21, 21, 28])   # 4 fish (incomplete), total 91
      rows = Build.call(tournament: @t)
      assert_equal partial_heavier.id, rows.first[:entry].id, "heaviest bag wins regardless of fish count"
      assert full_lighter.id == rows.last[:entry].id
      # sanity: the winner is the incomplete basket, proving no complete-first tiering
      assert_not rows.first[:complete], "winner is the 4-fish partial basket"
    end
  end
end
