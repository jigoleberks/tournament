require "test_helper"

module Catches
  class ApplyJudgeActionBingoTest < ActiveSupport::TestCase
    test "disqualifying a bingo catch broadcasts the bingo tournament" do
      club = Club.create!(name: "C")
      walleye, = create_bingo_species!
      t = Tournament.new(club: club, name: "B", mode: :solo, format: :bingo,
                         starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
      t.save!
      owner = User.create!(name: "A", email: "a@example.com")
      judge = User.create!(name: "J", email: "j@example.com")
      e = t.tournament_entries.create!
      e.tournament_entry_members.create!(user: owner)
      c = create(:catch, user: owner, species: walleye, length_inches: 15, length_unit: "inches",
                 captured_at_device: 1.hour.ago, status: :synced)

      broadcast_targets = with_broadcast_spy do
        Catches::ApplyJudgeAction.call(tournament: t, catch: c, judge: judge,
                                       action: :disqualify, note: "test")
      end

      assert_includes broadcast_targets, t.id
      assert c.reload.disqualified?
    end

    test "broadcasts the bingo tournament even when the catch owner is also a judge on it" do
      club = Club.create!(name: "C")
      walleye, = create_bingo_species!
      t = Tournament.new(club: club, name: "B", mode: :solo, format: :bingo,
                         starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
      t.save!
      owner = User.create!(name: "A", email: "owner-judge@example.com")
      judge = User.create!(name: "J", email: "acting-judge@example.com")
      e = t.tournament_entries.create!
      e.tournament_entry_members.create!(user: owner)
      # Owner is entered AND a judge — ActiveForUser would drop this tournament,
      # and bingo has no active placement to recover it from.
      TournamentJudge.create!(tournament: t, user: owner)
      c = create(:catch, user: owner, species: walleye, length_inches: 15, length_unit: "inches",
                 captured_at_device: 1.hour.ago, status: :synced)

      broadcast_targets = with_broadcast_spy do
        Catches::ApplyJudgeAction.call(tournament: t, catch: c, judge: judge,
                                       action: :disqualify, note: "test")
      end

      assert_includes broadcast_targets, t.id
    end
  end
end
