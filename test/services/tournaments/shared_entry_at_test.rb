require "test_helper"

module Tournaments
  class SharedEntryAtTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @a = create(:user, club: @club)
      @b = create(:user, club: @club)
    end

    test "returns the shared entry when both users are members and the tournament is active" do
      t = create(:tournament, club: @club, mode: :team, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: @a)
      create(:tournament_entry_member, tournament_entry: entry, user: @b)

      assert_equal entry, SharedEntryAt.call(user_a: @a, user_b: @b, club: @club, at: Time.current)
    end

    test "returns nil when users are in different entries of the same tournament" do
      t = create(:tournament, club: @club, mode: :team, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      e1 = create(:tournament_entry, tournament: t)
      e2 = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: e1, user: @a)
      create(:tournament_entry_member, tournament_entry: e2, user: @b)

      assert_nil SharedEntryAt.call(user_a: @a, user_b: @b, club: @club, at: Time.current)
    end

    test "returns nil when the tournament window doesn't contain the time" do
      t = create(:tournament, club: @club, mode: :team, starts_at: 3.days.ago, ends_at: 2.days.ago)
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: @a)
      create(:tournament_entry_member, tournament_entry: entry, user: @b)

      assert_nil SharedEntryAt.call(user_a: @a, user_b: @b, club: @club, at: Time.current)
    end

    test "open-ended tournament (ends_at nil) counts as still active" do
      t = create(:tournament, club: @club, mode: :team, starts_at: 1.day.ago, ends_at: nil)
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: @a)
      create(:tournament_entry_member, tournament_entry: entry, user: @b)

      assert_equal entry, SharedEntryAt.call(user_a: @a, user_b: @b, club: @club, at: Time.current)
    end

    test "returns nil when one user belongs to a different club" do
      other_club = create(:club)
      foreigner = create(:user, club: other_club)
      t = create(:tournament, club: @club, mode: :team, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: @a)

      assert_nil SharedEntryAt.call(user_a: @a, user_b: foreigner, club: @club, at: Time.current)
    end

    test "returns nil when called with the same user twice" do
      t = create(:tournament, club: @club, mode: :team, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: @a)

      assert_nil SharedEntryAt.call(user_a: @a, user_b: @a, club: @club, at: Time.current)
    end
  end
end
