require "test_helper"

module Tournaments
  class ActiveForUserTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @user = create(:user, club: @club)
      @other = create(:user, club: @club)
    end

    test "returns tournaments where the user has an entry and the window contains now" do
      t_in = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      entry = create(:tournament_entry, tournament: t_in)
      create(:tournament_entry_member, tournament_entry: entry, user: @user)

      t_other_user = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      e2 = create(:tournament_entry, tournament: t_other_user)
      create(:tournament_entry_member, tournament_entry: e2, user: @other)

      result = ActiveForUser.call(user: @user, at: Time.current)
      assert_equal [t_in], result
    end

    test "open-ended ends_at is treated as still active" do
      # Legacy state: ends_at is now required for new records, but the query
      # still defends against NULL. Persist one bypassing validation.
      t = build(:tournament, club: @club, starts_at: 1.day.ago, ends_at: nil)
      t.save!(validate: false)
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: @user)

      assert_includes ActiveForUser.call(user: @user, at: Time.current), t
    end

    test "tournaments before starts_at are excluded" do
      t = create(:tournament, club: @club, starts_at: 1.hour.from_now)
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: @user)

      assert_empty ActiveForUser.call(user: @user, at: Time.current)
    end

    # A tournament with two judges assigned once fanned out to one row per judge,
    # so PlaceInSlots iterated the same entry twice and appended a second
    # placement in the append-only formats (Hidden Length, Tagged).
    test "a tournament with several judges is returned exactly once" do
      t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: @user)
      2.times { create(:tournament_judge, tournament: t, user: create(:user, club: @club)) }

      assert_equal [t], ActiveForUser.call(user: @user, at: Time.current)
      assert_equal [{ tournament: t, entry: entry }],
                   ActiveForUser.with_entries(user: @user, at: Time.current)
    end

    # A judge must never be scored in a tournament they judge. New judge/entrant
    # rows are blocked by mutual-exclusion validations, but legacy tournaments
    # predating those validations can still hold both rows for one user — the
    # active-for-user query must exclude such a tournament for that user so
    # PlaceInSlots never places their catches.
    test "excludes a tournament where the user is both an entrant and a judge (legacy overlap)" do
      t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: @user)
      # Bypass validation to reproduce a pre-existing judge+entrant overlap row.
      TournamentJudge.new(tournament: t, user: @user).save!(validate: false)

      assert_empty ActiveForUser.call(user: @user, at: Time.current)
      assert_empty ActiveForUser.with_entries(user: @user, at: Time.current)
    end

    test "returns the tournament_entry alongside (as a hash result)" do
      t = create(:tournament, club: @club, starts_at: 1.hour.ago)
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: @user)

      result = ActiveForUser.with_entries(user: @user, at: Time.current)
      assert_equal [{ tournament: t, entry: entry }], result
    end
  end
end
