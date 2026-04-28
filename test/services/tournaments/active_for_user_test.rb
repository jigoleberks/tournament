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
      t = create(:tournament, club: @club, starts_at: 1.day.ago, ends_at: nil)
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

    test "returns the tournament_entry alongside (as a hash result)" do
      t = create(:tournament, club: @club, starts_at: 1.hour.ago)
      entry = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: @user)

      result = ActiveForUser.with_entries(user: @user, at: Time.current)
      assert_equal [{ tournament: t, entry: entry }], result
    end
  end
end
