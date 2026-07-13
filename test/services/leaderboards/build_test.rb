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

    test "dispatches each format to its matching ranker" do
      walleye = create(:species)
      # Per-format tournament builders; several formats skip validation and add a
      # scoring slot, matching how those records are really persisted.
      builders = {
        standard: -> {
          create(:tournament, club: @club, format: :standard,
                 starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
        },
        big_fish_season: -> {
          t = build(:tournament, club: @club, format: :big_fish_season, mode: :solo,
                    starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
          t.save!(validate: false)
          create(:scoring_slot, tournament: t, species: walleye, slot_count: 3)
          t.reload
        },
        hidden_length: -> {
          t = build(:tournament, club: @club, format: :hidden_length, mode: :solo,
                    starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
          t.save!(validate: false)
          create(:scoring_slot, tournament: t, species: walleye, slot_count: 1)
          t.reload
        },
        biggest_vs_smallest: -> {
          t = build(:tournament, club: @club, format: :biggest_vs_smallest, mode: :solo,
                    starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
          t.save!(validate: false)
          create(:scoring_slot, tournament: t, species: walleye, slot_count: 1)
          t.reload
        },
        fish_train: -> {
          t = build(:tournament, club: @club, format: :fish_train, mode: :solo,
                    starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                    train_cars: [walleye.id, walleye.id, walleye.id])
          t.save!(validate: false)
          create(:scoring_slot, tournament: t, species: walleye, slot_count: 1)
          t.reload
        }
      }

      called = []
      # Stub every ranker to record its own name (accepting any extra kwargs, e.g.
      # HiddenLength's `tournament:`), then check each format routes to exactly one.
      recorder = ->(name) { ->(rows, **) { called << name; rows } }
      with_class_method_stub(Leaderboards::Rankers::Standard,          :call, recorder.call(:standard)) do
        with_class_method_stub(Leaderboards::Rankers::BigFishSeason,     :call, recorder.call(:big_fish_season)) do
          with_class_method_stub(Leaderboards::Rankers::HiddenLength,     :call, recorder.call(:hidden_length)) do
            with_class_method_stub(Leaderboards::Rankers::BiggestVsSmallest, :call, recorder.call(:biggest_vs_smallest)) do
              with_class_method_stub(Leaderboards::Rankers::FishTrain,        :call, recorder.call(:fish_train)) do
                builders.each do |format, build_tournament|
                  called.clear
                  Build.call(tournament: build_tournament.call)
                  assert_equal [format], called, "expected #{format} to dispatch to Rankers::#{format.to_s.camelize}"
                end
              end
            end
          end
        end
      end
    end

    test "dispatches to Rankers::Tagged for tagged tournaments and ranks by ticket count" do
      club = create(:club)
      tagged = Species.find_or_create_by!(name: "Tagged Walleye")
      user_a = create(:user, club: club, name: "Aaron")
      user_b = create(:user, club: club, name: "Bea")

      t = build(:tournament, club: club, format: :tagged, mode: :solo,
                starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      t.scoring_slots.build(species: tagged, slot_count: 1)
      t.save!

      entry_a = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry_a, user: user_a)
      entry_b = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry_b, user: user_b)

      # Bea catches 2, Aaron catches 1 — Bea should rank first.
      2.times do |i|
        Catches::PlaceInSlots.call(
          catch: create(:catch, user: user_b, species: tagged, length_inches: 18.0,
                        tag_number: "B#{i}", captured_at_device: 30.minutes.ago)
        )
      end
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user_a, species: tagged, length_inches: 18.0,
                      tag_number: "A1", captured_at_device: 30.minutes.ago)
      )

      result = Leaderboards::Build.call(tournament: t)
      assert_equal [entry_b.id, entry_a.id], result.map { |r| r[:entry].id }
      assert_equal 2, result.first[:total]   # Total = ticket count for tagged
      assert_equal 1, result.last[:total]
    end

    test "tagged ranker breaks ticket-count ties by earliest catch" do
      club = create(:club)
      tagged = Species.find_or_create_by!(name: "Tagged Walleye")
      user_a = create(:user, club: club, name: "Aaron")
      user_b = create(:user, club: club, name: "Bea")

      t = build(:tournament, club: club, format: :tagged, mode: :solo,
                starts_at: 2.hours.ago, ends_at: 1.hour.from_now)
      t.scoring_slots.build(species: tagged, slot_count: 1)
      t.save!

      entry_a = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry_a, user: user_a)
      entry_b = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry_b, user: user_b)

      # One ticket each; Aaron caught earlier so should rank first.
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user_a, species: tagged, length_inches: 18.0,
                      tag_number: "A1", captured_at_device: 90.minutes.ago)
      )
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user_b, species: tagged, length_inches: 18.0,
                      tag_number: "B1", captured_at_device: 30.minutes.ago)
      )

      result = Leaderboards::Build.call(tournament: t)
      assert_equal [entry_a.id, entry_b.id], result.map { |r| r[:entry].id }
    end

    test "fish rows carry the catch's length_unit" do
      user  = create(:user, club: @club)
      entry = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: entry, user: user)

      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: @walleye, length_inches: 14.47,
                      length_unit: "centimeters", captured_at_device: 10.minutes.ago)
      )

      rows = Leaderboards::Build.call(tournament: @tournament)
      fish = rows.flat_map { |r| r[:fish] }
      assert_equal "centimeters", fish.first[:length_unit]
    end

    test "tagged fish list is ordered chronologically (oldest ticket first)" do
      club = create(:club)
      tagged = Species.find_or_create_by!(name: "Tagged Walleye")
      user = create(:user, club: club, name: "Aaron")

      t = build(:tournament, club: club, format: :tagged, mode: :solo,
                starts_at: 2.hours.ago, ends_at: 1.hour.from_now)
      t.scoring_slots.build(species: tagged, slot_count: 1)
      t.save!

      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: user)

      # Insert in length-desc order; only an explicit timestamp sort puts
      # the earliest tag first in the list.
      Catches::PlaceInSlots.call(catch: create(:catch, user: user, species: tagged,
        length_inches: 22.0, tag_number: "EARLY", captured_at_device: 90.minutes.ago))
      Catches::PlaceInSlots.call(catch: create(:catch, user: user, species: tagged,
        length_inches: 18.0, tag_number: "MID",   captured_at_device: 60.minutes.ago))
      Catches::PlaceInSlots.call(catch: create(:catch, user: user, species: tagged,
        length_inches: 15.0, tag_number: "LATE",  captured_at_device: 30.minutes.ago))

      row = Leaderboards::Build.call(tournament: t).first
      assert_equal %w[EARLY MID LATE], row[:fish].map { |f| f[:tag_number] }
    end

    test "routes beat_the_average to the BeatTheAverage ranker and returns the winner first" do
      t = build(:tournament, club: @club, format: :beat_the_average, mode: :solo,
                starts_at: 3.hours.ago, ends_at: 1.hour.ago)
      t.scoring_slots.build(species: @walleye, slot_count: 1)
      t.save!

      a = create(:user, club: @club, name: "A")
      b = create(:user, club: @club, name: "B")
      ea = create(:tournament_entry, tournament: t)
      eb = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: ea, user: a)
      create(:tournament_entry_member, tournament_entry: eb, user: b)

      # Combined average = (12 + 30 + 18) / 3 = 20.00
      # Distances: 12 -> 8, 30 -> 10, 18 -> 2 -> the 18" catch is the unambiguous winner.
      Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: @walleye, length_inches: 12, captured_at_device: 2.hours.ago))
      Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: @walleye, length_inches: 30, captured_at_device: 2.hours.ago))
      winner = create(:catch, user: b, species: @walleye, length_inches: 18, captured_at_device: 2.hours.ago)
      Catches::PlaceInSlots.call(catch: winner)

      result = Leaderboards::Build.call(tournament: t)
      assert_equal 3, result.size
      assert_equal winner.id, result.first[:fish].first[:id]
    end

    test "smallest_fish ranks complete entries by lowest total and orders row fish smallest-first" do
      t = create(:tournament, club: @club, format: :smallest_fish, mode: :solo, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: t, species: @walleye, slot_count: 2)

      a = create(:user, club: @club, name: "A")
      b = create(:user, club: @club, name: "B")
      ea = create(:tournament_entry, tournament: t)
      eb = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: ea, user: a)
      create(:tournament_entry_member, tournament_entry: eb, user: b)

      # A: 10 + 12 = 22. B: 8 + 9 = 17 (lower total → wins).
      Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: @walleye, length_inches: 12))
      Catches::PlaceInSlots.call(catch: create(:catch, user: a, species: @walleye, length_inches: 10))
      Catches::PlaceInSlots.call(catch: create(:catch, user: b, species: @walleye, length_inches: 9))
      Catches::PlaceInSlots.call(catch: create(:catch, user: b, species: @walleye, length_inches: 8))

      result = Build.call(tournament: t)

      assert_equal ["B", "A"], result.map { |row| row[:entry].users.first.name }, "lowest total wins"
      # Top row (B) fish ordered smallest-first.
      assert_equal [8, 9], result.first[:fish].map { |f| f[:length_inches].to_i }
    end

    test "random_bag build assigns targets and ranks entries by closest bag" do
      club = create(:club)
      species = create(:species)
      t = build(:tournament, club: club, format: :random_bag, mode: :solo,
                target_min_inches: 85, target_max_inches: 85,      # fixed target -> deterministic
                starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      t.scoring_slots.build(species: species, slot_count: 1)
      t.save!

      near = create(:tournament_entry, tournament: t)
      far  = create(:tournament_entry, tournament: t)
      # near: 43+43 = 86 (1 off 85). far: 40+40 = 80 (5 off 85).
      [[near, 43], [far, 40]].each do |entry, len|
        2.times do
          idx = entry.catch_placements.count
          create(:catch_placement, tournament: t, tournament_entry: entry, species: species,
                 slot_index: idx,
                 catch: create(:catch, species: species, length_inches: len,
                               captured_at_device: 30.minutes.ago))
        end
      end

      board = Leaderboards::Build.call(tournament: t)
      assert_equal BigDecimal("85"), near.reload.random_bag_target_inches, "target lazily assigned"
      assert_equal near.id, board.first[:entry].id, "closest bag ranks first"
      assert_equal BigDecimal("1"), board.first[:distance]
    end

    test "random_bag QualifiedRows ranks the closest team as the winner" do
      club = create(:club); species = create(:species)
      t = build(:tournament, club: club, format: :random_bag, mode: :team,
                target_min_inches: 85, target_max_inches: 85,
                starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      t.scoring_slots.build(species: species, slot_count: 1); t.save!
      winner = create(:tournament_entry, tournament: t)  # 43+43 = 86, 1 off
      runner = create(:tournament_entry, tournament: t)  # 40+40 = 80, 5 off
      [[winner, 43], [runner, 40]].each do |entry, len|
        2.times do |i|
          create(:catch_placement, tournament: t, tournament_entry: entry, species: species, slot_index: i,
                 catch: create(:catch, species: species, length_inches: len, captured_at_device: 30.minutes.ago))
        end
      end
      board = Leaderboards::Build.call(tournament: t)
      qualified = Leaderboards::QualifiedRows.call(tournament: t, rows: board)
      assert_equal winner.id, qualified.first[:entry].id
      assert_equal 2, qualified.size, "both teams qualify (one row per entry)"
    end
  end
end
