require "test_helper"

module Catches
  class PromoteBackupTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @user = create(:user, club: @club)
      @t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 2)
      @entry = create(:tournament_entry, tournament: @t)
      # Backdate to before tournament start so EntryEligibility's per-member window
      # resolves to tournament.starts_at (not the DB insert time).
      create(:tournament_entry_member, tournament_entry: @entry, user: @user)
        .update_column(:created_at, 2.hours.ago)
    end

    test "promotes the largest eligible unplaced catch into the freed slot" do
      placed_a = create(:catch, user: @user, species: @walleye, length_inches: 22, captured_at_device: 30.minutes.ago)
      placed_b = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 25.minutes.ago)
      Catches::PlaceInSlots.call(catch: placed_a)
      Catches::PlaceInSlots.call(catch: placed_b)

      backup_small = create(:catch, user: @user, species: @walleye, length_inches: 14, captured_at_device: 20.minutes.ago)
      backup_big   = create(:catch, user: @user, species: @walleye, length_inches: 16, captured_at_device: 15.minutes.ago)
      Catches::PlaceInSlots.call(catch: backup_small)
      Catches::PlaceInSlots.call(catch: backup_big)
      assert_equal 0, ::CatchPlacement.where(catch_id: [backup_small.id, backup_big.id]).count

      freed = placed_b.catch_placements.first
      freed.update!(active: false)

      Catches::PromoteBackup.call(freed_placement: freed)
      promoted = @entry.catch_placements.active.where(species: @walleye, slot_index: freed.slot_index).first
      assert_equal backup_big.id, promoted.catch_id
    end

    test "creates nothing when there are no backup candidates" do
      placed = create(:catch, user: @user, species: @walleye, length_inches: 22)
      Catches::PlaceInSlots.call(catch: placed)
      freed = placed.catch_placements.first
      freed.update!(active: false)

      assert_nil Catches::PromoteBackup.call(freed_placement: freed)
    end

    test "skips catches outside the tournament time window" do
      placed = create(:catch, user: @user, species: @walleye, length_inches: 22)
      Catches::PlaceInSlots.call(catch: placed)
      backup_pre  = create(:catch, user: @user, species: @walleye, length_inches: 19, captured_at_device: 2.hours.ago)
      backup_post = create(:catch, user: @user, species: @walleye, length_inches: 19, captured_at_device: 2.hours.from_now)

      freed = placed.catch_placements.first
      freed.update!(active: false)

      assert_nil Catches::PromoteBackup.call(freed_placement: freed)
      assert_not ::CatchPlacement.exists?(catch_id: [backup_pre.id, backup_post.id], active: true)
    end

    test "skips disqualified catches" do
      placed = create(:catch, user: @user, species: @walleye, length_inches: 22)
      Catches::PlaceInSlots.call(catch: placed)
      backup = create(:catch, user: @user, species: @walleye, length_inches: 19, status: :disqualified)

      freed = placed.catch_placements.first
      freed.update!(active: false)

      assert_nil Catches::PromoteBackup.call(freed_placement: freed)
    end

    test "promotes a previously-bumped (inactive) catch when it's the largest available" do
      first  = create(:catch, user: @user, species: @walleye, length_inches: 16, captured_at_device: 30.minutes.ago)
      Catches::PlaceInSlots.call(catch: first)
      second = create(:catch, user: @user, species: @walleye, length_inches: 14, captured_at_device: 25.minutes.ago)
      Catches::PlaceInSlots.call(catch: second)
      bumper = create(:catch, user: @user, species: @walleye, length_inches: 22, captured_at_device: 20.minutes.ago)
      Catches::PlaceInSlots.call(catch: bumper)
      assert_empty second.reload.catch_placements.where(active: true), "second should be bumped"

      freed = bumper.catch_placements.active.first
      freed.update!(active: false)

      Catches::PromoteBackup.call(freed_placement: freed)
      promoted = @entry.catch_placements.active.where(species: @walleye, slot_index: freed.slot_index).first
      assert_equal second.id, promoted.catch_id
    end

    test "eligible? filters out-of-lake catch in a local tournament" do
      local_t = create(:tournament, club: @club, local: true, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: local_t, species: @walleye, slot_count: 1)
      local_entry = create(:tournament_entry, tournament: local_t)
      create(:tournament_entry_member, tournament_entry: local_entry, user: @user)
        .update_column(:created_at, 2.hours.ago)

      placed = create(:catch, user: @user, species: @walleye, length_inches: 22, captured_at_device: 30.minutes.ago)
      Catches::PlaceInSlots.call(catch: placed)

      # out_of_lake is longer, so it would win on length — but eligible? must reject it
      out_of_lake = create(:catch, user: @user, species: @walleye, length_inches: 20,
                                   captured_at_device: 25.minutes.ago,
                                   latitude: 49.9, longitude: -97.1)
      in_lake     = create(:catch, user: @user, species: @walleye, length_inches: 17,
                                   captured_at_device: 20.minutes.ago,
                                   latitude: 49.41, longitude: -103.62)

      freed = placed.catch_placements.where(tournament: local_t).first
      freed.update!(active: false)

      Catches::PromoteBackup.call(freed_placement: freed)
      promoted = local_entry.catch_placements.active.where(species: @walleye, slot_index: freed.slot_index).first
      assert_not_nil promoted, "expected a catch to be promoted into the freed slot"
      assert_equal in_lake.id, promoted.catch_id,
                   "expected the in-lake catch to be promoted, not the out-of-lake catch"
    end

    test "eligible? filters out-of-province catch in an away tournament" do
      away_t = create(:tournament, club: @club, local: false, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: away_t, species: @walleye, slot_count: 1)
      away_entry = create(:tournament_entry, tournament: away_t)
      create(:tournament_entry_member, tournament_entry: away_entry, user: @user)
        .update_column(:created_at, 2.hours.ago)

      placed = create(:catch, user: @user, species: @walleye, length_inches: 22, captured_at_device: 30.minutes.ago)
      Catches::PlaceInSlots.call(catch: placed)

      # out_of_province is longer, so it would win on length — but eligible? must reject it
      out_of_province = create(:catch, user: @user, species: @walleye, length_inches: 20,
                                       captured_at_device: 25.minutes.ago,
                                       latitude: 49.9, longitude: -97.1)
      in_province     = create(:catch, user: @user, species: @walleye, length_inches: 17,
                                       captured_at_device: 20.minutes.ago,
                                       latitude: 50.45, longitude: -104.61)

      freed = placed.catch_placements.where(tournament: away_t).first
      freed.update!(active: false)

      Catches::PromoteBackup.call(freed_placement: freed)
      promoted = away_entry.catch_placements.active.where(species: @walleye, slot_index: freed.slot_index).first
      assert_not_nil promoted, "expected a catch to be promoted into the freed slot"
      assert_equal in_province.id, promoted.catch_id,
                   "expected the in-province catch to be promoted, not the out-of-province catch"
    end

    test "considers a teammate's catch on a team entry" do
      team_t = create(:tournament, club: @club, mode: :team, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: team_t, species: @walleye, slot_count: 1)
      teammate = create(:user, club: @club)
      team_entry = create(:tournament_entry, tournament: team_t, name: "Boat")
      create(:tournament_entry_member, tournament_entry: team_entry, user: @user)
        .update_column(:created_at, 2.hours.ago)
      create(:tournament_entry_member, tournament_entry: team_entry, user: teammate)
        .update_column(:created_at, 2.hours.ago)

      placed = create(:catch, user: @user, species: @walleye, length_inches: 22, captured_at_device: 30.minutes.ago)
      Catches::PlaceInSlots.call(catch: placed)
      backup = create(:catch, user: teammate, species: @walleye, length_inches: 18, captured_at_device: 20.minutes.ago)

      freed = placed.catch_placements.where(tournament: team_t).first
      freed.update!(active: false)

      Catches::PromoteBackup.call(freed_placement: freed)
      promoted = team_entry.catch_placements.active.first
      assert_equal backup.id, promoted.catch_id
    end

    test "does not promote a catch logged before the candidate joined the entry" do
      # @entry is solo-mode by default; build a team tournament so we can have two members.
      team_t = create(:tournament, club: @club, mode: :team, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: team_t, species: @walleye, slot_count: 1)
      team_entry = create(:tournament_entry, tournament: team_t)
      create(:tournament_entry_member, tournament_entry: team_entry, user: @user)
      late = create(:user, club: @club)
      late_member = create(:tournament_entry_member, tournament_entry: team_entry, user: late)
      late_member.update_column(:created_at, 30.minutes.ago)

      # @user has a placed catch in slot 0; free it and try to promote.
      placed = create(:catch, user: @user, species: @walleye, length_inches: 18, captured_at_device: 30.minutes.ago)
      Catches::PlaceInSlots.call(catch: placed)
      freed = placed.catch_placements.where(tournament: team_t).first
      freed.update!(active: false)

      # The Day-2-joiner has a bigger catch from BEFORE they joined — must not be promoted.
      pre_join = create(:catch, user: late, species: @walleye, length_inches: 30, captured_at_device: 1.hour.ago)

      Catches::PromoteBackup.call(freed_placement: freed)

      active = team_entry.catch_placements.active.where(species: @walleye, slot_index: freed.slot_index)
      assert_equal 0, active.count, "no candidate should be promoted; the only larger catch is pre-membership"
      assert_not ::CatchPlacement.exists?(catch_id: pre_join.id, active: true)
    end
  end
end
