require "test_helper"

module Tournaments
  class TeammatesForTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @user = create(:user, club: @club)
      @tournament = create(:tournament, club: @club, mode: :team)
      @entry = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: @entry, user: @user)
    end

    test "returns same-entry teammates, ordered by name, excluding self" do
      bob = create(:user, club: @club, name: "Bob")
      alice = create(:user, club: @club, name: "Alice")
      create(:tournament_entry_member, tournament_entry: @entry, user: bob)
      create(:tournament_entry_member, tournament_entry: @entry, user: alice)

      result = TeammatesFor.call(user: @user, tournament: @tournament).to_a
      assert_equal [alice, bob], result
    end

    test "excludes members of other entries in the same tournament" do
      mate = create(:user, club: @club)
      create(:tournament_entry_member, tournament_entry: @entry, user: mate)
      other_entry = create(:tournament_entry, tournament: @tournament)
      stranger = create(:user, club: @club)
      create(:tournament_entry_member, tournament_entry: other_entry, user: stranger)

      result = TeammatesFor.call(user: @user, tournament: @tournament).to_a
      assert_equal [mate], result
    end

    test "excludes deactivated teammates" do
      gone = create(:user, club: @club, deactivated_at: 1.day.ago)
      create(:tournament_entry_member, tournament_entry: @entry, user: gone)

      assert_empty TeammatesFor.call(user: @user, tournament: @tournament).to_a
    end

    test "returns empty when user has no entry in the tournament" do
      lonely = create(:tournament, club: @club)
      assert_empty TeammatesFor.call(user: @user, tournament: lonely).to_a
    end
  end
end
