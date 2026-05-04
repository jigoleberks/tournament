require "test_helper"

module Catches
  class EntryEligibilityTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @tournament = create(:tournament, club: @club, starts_at: 2.hours.ago, ends_at: 2.hours.from_now, local: false)
      @entry = create(:tournament_entry, tournament: @tournament)
      @user = create(:user, club: @club)
      @member = create(:tournament_entry_member, tournament_entry: @entry, user: @user)
      # Backdate the membership to the tournament start, so it doesn't cut anything off by accident.
      @member.update_column(:created_at, 2.hours.ago)
    end

    test "includes a catch by a member, in window, in Sask, matching species" do
      c = create(:catch, user: @user, species: @walleye, length_inches: 22,
                         captured_at_device: 30.minutes.ago,
                         latitude: 50.45, longitude: -104.61)
      assert_includes EntryEligibility.candidates_for(entry: @entry, tournament: @tournament, species: @walleye), c
    end

    test "excludes a catch logged before the user joined this entry" do
      team_tournament = create(:tournament, club: @club, starts_at: 2.hours.ago, ends_at: 2.hours.from_now, local: false, mode: :team)
      team_entry = create(:tournament_entry, tournament: team_tournament)
      early_member = create(:tournament_entry_member, tournament_entry: team_entry, user: @user)
      early_member.update_column(:created_at, 2.hours.ago)
      late = create(:user, club: @club)
      late_member = create(:tournament_entry_member, tournament_entry: team_entry, user: late)
      late_member.update_column(:created_at, 30.minutes.ago)
      pre_join = create(:catch, user: late, species: @walleye, length_inches: 30,
                                captured_at_device: 1.hour.ago,
                                latitude: 50.45, longitude: -104.61)
      post_join = create(:catch, user: late, species: @walleye, length_inches: 18,
                                  captured_at_device: 10.minutes.ago,
                                  latitude: 50.45, longitude: -104.61)
      result = EntryEligibility.candidates_for(entry: team_entry, tournament: team_tournament, species: @walleye)
      assert_not_includes result, pre_join
      assert_includes result, post_join
    end

    test "excludes disqualified catches" do
      c = create(:catch, user: @user, species: @walleye, length_inches: 22,
                         captured_at_device: 30.minutes.ago,
                         latitude: 50.45, longitude: -104.61,
                         status: :disqualified)
      assert_not_includes EntryEligibility.candidates_for(entry: @entry, tournament: @tournament, species: @walleye), c
    end

    test "excludes catches outside the tournament window" do
      before = create(:catch, user: @user, species: @walleye, length_inches: 22,
                              captured_at_device: 3.hours.ago,
                              latitude: 50.45, longitude: -104.61)
      after  = create(:catch, user: @user, species: @walleye, length_inches: 22,
                              captured_at_device: 3.hours.from_now,
                              latitude: 50.45, longitude: -104.61)
      result = EntryEligibility.candidates_for(entry: @entry, tournament: @tournament, species: @walleye)
      assert_not_includes result, before
      assert_not_includes result, after
    end

    test "excludes catches whose GPS is outside Saskatchewan" do
      out = create(:catch, user: @user, species: @walleye, length_inches: 22,
                           captured_at_device: 30.minutes.ago,
                           latitude: 51.05, longitude: -114.07) # Calgary
      assert_not_includes EntryEligibility.candidates_for(entry: @entry, tournament: @tournament, species: @walleye), out
    end

    test "includes a catch with no GPS" do
      c = create(:catch, user: @user, species: @walleye, length_inches: 22,
                         captured_at_device: 30.minutes.ago,
                         latitude: nil, longitude: nil)
      assert_includes EntryEligibility.candidates_for(entry: @entry, tournament: @tournament, species: @walleye), c
    end

    test "for a local tournament, requires the lake polygon" do
      local_t = create(:tournament, club: @club, starts_at: 2.hours.ago, ends_at: 2.hours.from_now, local: true)
      local_entry = create(:tournament_entry, tournament: local_t)
      local_member = create(:tournament_entry_member, tournament_entry: local_entry, user: @user)
      local_member.update_column(:created_at, 2.hours.ago)
      # Regina coords are in Sask but not in any lake polygon by default fixture.
      regina = create(:catch, user: @user, species: @walleye, length_inches: 22,
                              captured_at_device: 30.minutes.ago,
                              latitude: 50.45, longitude: -104.61)
      result = EntryEligibility.candidates_for(entry: local_entry, tournament: local_t, species: @walleye)
      assert_not_includes result, regina
    end

    test "orders by length_inches DESC then captured_at_device ASC" do
      mid_old = create(:catch, user: @user, species: @walleye, length_inches: 20,
                               captured_at_device: 90.minutes.ago,
                               latitude: 50.45, longitude: -104.61)
      mid_new = create(:catch, user: @user, species: @walleye, length_inches: 20,
                               captured_at_device: 30.minutes.ago,
                               latitude: 50.45, longitude: -104.61)
      big = create(:catch, user: @user, species: @walleye, length_inches: 24,
                           captured_at_device: 30.minutes.ago,
                           latitude: 50.45, longitude: -104.61)
      result = EntryEligibility.candidates_for(entry: @entry, tournament: @tournament, species: @walleye)
      assert_equal [big.id, mid_old.id, mid_new.id], result.map(&:id)
    end

    test "excludes catches whose species does not match" do
      perch = create(:species, club: @club)
      c = create(:catch, user: @user, species: perch, length_inches: 22,
                         captured_at_device: 30.minutes.ago,
                         latitude: 50.45, longitude: -104.61)
      assert_not_includes EntryEligibility.candidates_for(entry: @entry, tournament: @tournament, species: @walleye), c
    end
  end
end
