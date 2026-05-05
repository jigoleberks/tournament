require "test_helper"

module Placements
  class BroadcastLeaderboardTest < ActiveSupport::TestCase
    include ActionCable::TestHelper

    test "broadcasts a turbo stream replace to the tournament's channel" do
      club = create(:club)
      walleye = create(:species, club: club)
      t = create(:tournament, club: club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: t, species: walleye, slot_count: 1)
      user = create(:user, club: club)
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: user)

      catch_record = create(:catch, user: user, species: walleye, length_inches: 22)
      Catches::PlaceInSlots.call(catch: catch_record)

      assert_broadcasts("tournament:#{t.id}:leaderboard:full", 1) do
        BroadcastLeaderboard.call(tournament: t)
      end
    end

    test "blind+active: broadcasts to :full and to each entry's private stream" do
      club = create(:club)
      walleye = create(:species, club: club)
      t = create(:tournament, club: club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                 blind_leaderboard: true)
      create(:scoring_slot, tournament: t, species: walleye, slot_count: 1)
      e1 = create(:tournament_entry, tournament: t)
      e2 = create(:tournament_entry, tournament: t)

      assert_broadcasts("tournament:#{t.id}:leaderboard:full", 1) do
        assert_broadcasts("tournament:#{t.id}:leaderboard:entry:#{e1.id}", 1) do
          assert_broadcasts("tournament:#{t.id}:leaderboard:entry:#{e2.id}", 1) do
            BroadcastLeaderboard.call(tournament: t)
          end
        end
      end
    end

    test "non-blind tournament: only :full broadcasts" do
      club = create(:club)
      walleye = create(:species, club: club)
      t = create(:tournament, club: club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                 blind_leaderboard: false)
      create(:scoring_slot, tournament: t, species: walleye, slot_count: 1)
      e1 = create(:tournament_entry, tournament: t)

      assert_broadcasts("tournament:#{t.id}:leaderboard:full", 1) do
        assert_broadcasts("tournament:#{t.id}:leaderboard:entry:#{e1.id}", 0) do
          BroadcastLeaderboard.call(tournament: t)
        end
      end
    end

    test "ended-but-was-blind: broadcasts to :full AND :reveal" do
      club = create(:club)
      walleye = create(:species, club: club)
      t = create(:tournament, club: club, starts_at: 2.hours.ago, ends_at: 1.hour.ago,
                 blind_leaderboard: true)
      create(:scoring_slot, tournament: t, species: walleye, slot_count: 1)
      create(:tournament_entry, tournament: t)

      assert_broadcasts("tournament:#{t.id}:leaderboard:full", 1) do
        assert_broadcasts("tournament:#{t.id}:leaderboard:reveal", 1) do
          BroadcastLeaderboard.call(tournament: t)
        end
      end
    end

    test "ended non-blind tournament: does not broadcast to :reveal" do
      club = create(:club)
      walleye = create(:species, club: club)
      t = create(:tournament, club: club, starts_at: 2.hours.ago, ends_at: 1.hour.ago,
                 blind_leaderboard: false)
      create(:scoring_slot, tournament: t, species: walleye, slot_count: 1)
      create(:tournament_entry, tournament: t)

      assert_broadcasts("tournament:#{t.id}:leaderboard:reveal", 0) do
        BroadcastLeaderboard.call(tournament: t)
      end
    end
  end
end
