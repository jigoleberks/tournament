require "test_helper"

module Leaderboards
  class BuildTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @tournament = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: @tournament, species: @walleye, slot_count: 2)
    end

    test "ranks complete entries above incomplete entries even when incomplete has more length" do
      pike = create(:species)
      t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: t, species: @walleye, slot_count: 1)
      create(:scoring_slot, tournament: t, species: pike, slot_count: 1)

      a = create(:user, club: @club, name: "A")
      b = create(:user, club: @club, name: "B")
      ea = create(:tournament_entry, tournament: t)
      eb = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: ea, user: a)
      create(:tournament_entry_member, tournament_entry: eb, user: b)

      # A: 15 walleye + 15 pike = 30 total, complete (2/2 slots)
      Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: @walleye, length_inches: 15))
      Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: pike, length_inches: 15))
      # B: 50 walleye, no pike, 50 total but incomplete (1/2 slots)
      Catches::PlaceInSlots.call(catch: create(:catch, user: b, species: @walleye, length_inches: 50))

      result = Build.call(tournament: t)
      assert_equal ["A", "B"], result.map { |row| row[:entry].users.first.name }
    end

    test "two complete entries rank by total length cascade" do
      pike = create(:species)
      t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: t, species: @walleye, slot_count: 1)
      create(:scoring_slot, tournament: t, species: pike, slot_count: 1)

      a = create(:user, club: @club, name: "A")
      b = create(:user, club: @club, name: "B")
      ea = create(:tournament_entry, tournament: t)
      eb = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: ea, user: a)
      create(:tournament_entry_member, tournament_entry: eb, user: b)

      # Both complete; B has more total length.
      Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: @walleye, length_inches: 20))
      Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: pike, length_inches: 15))
      Catches::PlaceInSlots.call(catch: create(:catch, user: b, species: @walleye, length_inches: 25))
      Catches::PlaceInSlots.call(catch: create(:catch, user: b, species: pike, length_inches: 15))

      result = Build.call(tournament: t)
      assert_equal ["B", "A"], result.map { |row| row[:entry].users.first.name }
    end

    test "two incomplete entries rank by total length cascade" do
      pike = create(:species)
      t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: t, species: @walleye, slot_count: 1)
      create(:scoring_slot, tournament: t, species: pike, slot_count: 1)

      a = create(:user, club: @club, name: "A")
      b = create(:user, club: @club, name: "B")
      ea = create(:tournament_entry, tournament: t)
      eb = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: ea, user: a)
      create(:tournament_entry_member, tournament_entry: eb, user: b)

      # Both incomplete (only walleye, no pike); B has more length.
      Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: @walleye, length_inches: 20))
      Catches::PlaceInSlots.call(catch: create(:catch, user: b, species: @walleye, length_inches: 25))

      result = Build.call(tournament: t)
      assert_equal ["B", "A"], result.map { |row| row[:entry].users.first.name }
    end

    test "DQ that drops an entry below capacity demotes it below complete entries" do
      pike = create(:species)
      t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: t, species: @walleye, slot_count: 1)
      create(:scoring_slot, tournament: t, species: pike, slot_count: 1)

      a = create(:user, club: @club, name: "A")
      b = create(:user, club: @club, name: "B")
      ea = create(:tournament_entry, tournament: t)
      eb = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: ea, user: a)
      create(:tournament_entry_member, tournament_entry: eb, user: b)

      # Both complete initially. B has more length, so would beat A on length cascade alone.
      Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: @walleye, length_inches: 20))
      Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: pike, length_inches: 15))
      b_walleye = create(:catch, user: b, species: @walleye, length_inches: 25)
      b_pike    = create(:catch, user: b, species: pike,    length_inches: 20)
      Catches::PlaceInSlots.call(catch: b_walleye)
      Catches::PlaceInSlots.call(catch: b_pike)

      # Simulate a DQ on B's pike: deactivate the placement.
      CatchPlacement.find_by!(catch: b_pike, active: true).update!(active: false)

      result = Build.call(tournament: t)
      assert_equal ["A", "B"], result.map { |row| row[:entry].users.first.name }
    end

    test "zero-slot tournament: Build.call returns both entries with entry.id tiebreaker" do
      t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      # Intentionally no scoring_slot for t.

      a = create(:user, club: @club, name: "A")
      b = create(:user, club: @club, name: "B")
      ea = create(:tournament_entry, tournament: t)
      eb = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: ea, user: a)
      create(:tournament_entry_member, tournament_entry: eb, user: b)

      # Smoke test: a tournament without scoring slots should not raise.
      # No placements possible → all entries reach the final entry.id tiebreaker.
      result = Build.call(tournament: t)
      assert_equal [ea.id, eb.id], result.map { |row| row[:entry].id }
    end

    test "ranks entries by sum of active placement lengths, desc" do
      a = create(:user, club: @club, name: "A")
      b = create(:user, club: @club, name: "B")
      [a, b].each do |u|
        e = create(:tournament_entry, tournament: @tournament)
        create(:tournament_entry_member, tournament_entry: e, user: u)
      end

      ca1 = create(:catch, user: a, species: @walleye, length_inches: 20)
      ca2 = create(:catch, user: a, species: @walleye, length_inches: 17)
      cb1 = create(:catch, user: b, species: @walleye, length_inches: 22)
      [ca1, ca2, cb1].each { |c| Catches::PlaceInSlots.call(catch: c) }

      result = Build.call(tournament: @tournament)
      assert_equal ["A", "B"], result.map { |row| row[:entry].users.first.name }
      assert_equal [37, 22], result.map { |row| row[:total].to_i }
    end

    test "fish exposes angler_name and logged_by_name (nil for self-logged catches)" do
      @tournament.update!(mode: :team)
      a = create(:user, club: @club, name: "A")
      b = create(:user, club: @club, name: "B")
      e = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: e, user: a)
      create(:tournament_entry_member, tournament_entry: e, user: b)

      own = create(:catch, user: a, species: @walleye, length_inches: 22)
      teammate_logged = create(:catch, user: b, species: @walleye, length_inches: 18, logged_by_user: a)
      [own, teammate_logged].each { |c| Catches::PlaceInSlots.call(catch: c) }

      row = Build.call(tournament: @tournament).first
      by_id = row[:fish].index_by { |f| f[:id] }
      assert_equal "A", by_id[own.id][:angler_name]
      assert_nil by_id[own.id][:logged_by_name]
      assert_equal "B", by_id[teammate_logged.id][:angler_name]
      assert_equal "A", by_id[teammate_logged.id][:logged_by_name]
    end

    test "fish exposes approver_name when last judge action is an approve" do
      a = create(:user, club: @club, name: "A")
      e = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: e, user: a)
      judge = create(:user, club: @club, name: "Judge Judy")

      approved = create(:catch, user: a, species: @walleye, length_inches: 22)
      Catches::PlaceInSlots.call(catch: approved)
      create(:judge_action, judge_user: judge, catch: approved, action: :approve)

      unreviewed = create(:catch, user: a, species: @walleye, length_inches: 18)
      Catches::PlaceInSlots.call(catch: unreviewed)

      row = Build.call(tournament: @tournament).first
      by_id = row[:fish].index_by { |f| f[:id] }
      assert_equal "Judge Judy", by_id[approved.id][:approver_name]
      assert_nil by_id[unreviewed.id][:approver_name]
    end

    test "fish list per entry is ordered largest to smallest" do
      a = create(:user, club: @club, name: "A")
      e = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: e, user: a)

      # Insert in ascending order so the natural placement-id order is ascending too;
      # only an explicit length sort can yield [22, 18].
      [15, 18, 22].each do |len|
        Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: @walleye, length_inches: len))
      end

      row = Build.call(tournament: @tournament).first
      assert_equal [22, 18], row[:fish].map { |f| f[:length_inches].to_i },
                   "expected per-entry fish list to be ordered largest to smallest"
    end

    test "breaks total-length ties by largest single fish" do
      a = create(:user, club: @club, name: "A")
      b = create(:user, club: @club, name: "B")
      ea = create(:tournament_entry, tournament: @tournament)
      eb = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: ea, user: a)
      create(:tournament_entry_member, tournament_entry: eb, user: b)

      # A: 22 + 22 = 44, biggest fish 22
      # B: 24 + 20 = 44, biggest fish 24 → B wins tiebreaker
      [22, 22].each { |len| Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: @walleye, length_inches: len)) }
      [24, 20].each { |len| Catches::PlaceInSlots.call(catch: create(:catch, user: b, species: @walleye, length_inches: len)) }

      result = Build.call(tournament: @tournament)
      assert_equal ["B", "A"], result.map { |row| row[:entry].users.first.name }
    end

    test "breaks identical-fish ties by earliest captured_at_device" do
      a = create(:user, club: @club, name: "A")
      b = create(:user, club: @club, name: "B")
      ea = create(:tournament_entry, tournament: @tournament)
      eb = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: ea, user: a)
      create(:tournament_entry_member, tournament_entry: eb, user: b)

      earlier = create(:catch, user: a, species: @walleye, length_inches: 22, captured_at_device: 30.minutes.ago)
      later   = create(:catch, user: b, species: @walleye, length_inches: 22, captured_at_device: 10.minutes.ago)
      [earlier, later].each { |c| Catches::PlaceInSlots.call(catch: c) }

      result = Build.call(tournament: @tournament)
      assert_equal ["A", "B"], result.map { |row| row[:entry].users.first.name }
    end

    test "row exposes earliest_catch_at" do
      a = create(:user, club: @club, name: "A")
      ea = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: ea, user: a)
      early = create(:catch, user: a, species: @walleye, length_inches: 18, captured_at_device: 1.hour.ago)
      late  = create(:catch, user: a, species: @walleye, length_inches: 19, captured_at_device: 30.minutes.ago)
      [early, late].each { |c| Catches::PlaceInSlots.call(catch: c) }

      result = Build.call(tournament: @tournament)
      assert_in_delta early.captured_at_device, result.first[:earliest_catch_at], 1.second
    end

    test "dispatches to Rankers::Standard for standard tournaments" do
      t = create(:tournament, club: @club, format: :standard, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

      called = []
      with_class_method_stub(Leaderboards::Rankers::Standard,      :call, ->(rows) { called << :standard;        rows }) do
        with_class_method_stub(Leaderboards::Rankers::BigFishSeason, :call, ->(rows) { called << :big_fish_season; rows }) do
          Build.call(tournament: t)
        end
      end

      assert_equal [:standard], called
    end

    test "dispatches to Rankers::BigFishSeason for big_fish_season tournaments" do
      walleye = create(:species)
      t = build(:tournament, club: @club, format: :big_fish_season, mode: :solo,
                starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      t.save!(validate: false)
      create(:scoring_slot, tournament: t, species: walleye, slot_count: 3)
      t.reload

      called = []
      with_class_method_stub(Leaderboards::Rankers::Standard,      :call, ->(rows) { called << :standard;        rows }) do
        with_class_method_stub(Leaderboards::Rankers::BigFishSeason, :call, ->(rows) { called << :big_fish_season; rows }) do
          Build.call(tournament: t)
        end
      end

      assert_equal [:big_fish_season], called
    end

    test "dispatches to Rankers::HiddenLength for hidden_length tournaments" do
      walleye = create(:species)
      t = build(:tournament, club: @club, format: :hidden_length, mode: :solo,
                kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      t.save!(validate: false)
      create(:scoring_slot, tournament: t, species: walleye, slot_count: 1)
      t.reload

      called = []
      with_class_method_stub(Leaderboards::Rankers::Standard,      :call, ->(rows) { called << :standard;        rows }) do
        with_class_method_stub(Leaderboards::Rankers::BigFishSeason, :call, ->(rows) { called << :big_fish_season; rows }) do
          with_class_method_stub(Leaderboards::Rankers::HiddenLength, :call, ->(rows, tournament: nil) { called << :hidden_length;  rows }) do
            Build.call(tournament: t)
          end
        end
      end

      assert_equal [:hidden_length], called
    end

    test "dispatches to Rankers::BiggestVsSmallest for biggest_vs_smallest tournaments" do
      walleye = create(:species)
      t = build(:tournament, club: @club, format: :biggest_vs_smallest, mode: :solo,
                kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      t.save!(validate: false)
      create(:scoring_slot, tournament: t, species: walleye, slot_count: 1)
      t.reload

      called = []
      with_class_method_stub(Leaderboards::Rankers::Standard,         :call, ->(rows) { called << :standard;          rows }) do
        with_class_method_stub(Leaderboards::Rankers::BigFishSeason,  :call, ->(rows) { called << :big_fish_season;   rows }) do
          with_class_method_stub(Leaderboards::Rankers::HiddenLength, :call, ->(rows, tournament: nil) { called << :hidden_length;   rows }) do
            with_class_method_stub(Leaderboards::Rankers::BiggestVsSmallest, :call, ->(rows) { called << :biggest_vs_smallest; rows }) do
              Build.call(tournament: t)
            end
          end
        end
      end

      assert_equal [:biggest_vs_smallest], called
    end
  end
end
