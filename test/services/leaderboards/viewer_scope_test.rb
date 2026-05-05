require "test_helper"

module Leaderboards
  class ViewerScopeTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @blind_t = create(:tournament, club: @club,
                        starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                        blind_leaderboard: true)
      create(:scoring_slot, tournament: @blind_t, species: @walleye, slot_count: 1)

      @open_t = create(:tournament, club: @club,
                       starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                       blind_leaderboard: false)
      create(:scoring_slot, tournament: @open_t, species: @walleye, slot_count: 1)
    end

    test "non-blind tournament: every viewer gets :full" do
      member = create(:user, club: @club, role: :member)
      organizer = create(:user, club: @club, role: :organizer)

      assert_equal :full, ViewerScope.for(tournament: @open_t, user: member).visibility
      assert_equal :full, ViewerScope.for(tournament: @open_t, user: organizer).visibility
    end

    test "ended blind tournament: every viewer gets :full" do
      ended = create(:tournament, club: @club,
                     starts_at: 2.hours.ago, ends_at: 1.hour.ago,
                     blind_leaderboard: true)
      member = create(:user, club: @club, role: :member)

      assert_equal :full, ViewerScope.for(tournament: ended, user: member).visibility
    end

    test "blind+active: judge of this tournament gets :full" do
      judge = create(:user, club: @club, role: :member)
      create(:tournament_judge, tournament: @blind_t, user: judge)

      scope = ViewerScope.for(tournament: @blind_t, user: judge)
      assert_equal :full, scope.visibility
      assert_nil scope.entry_id
    end

    test "blind+active: entered angler gets :own_entry_only with their entry_id" do
      angler = create(:user, club: @club, role: :member)
      entry = create(:tournament_entry, tournament: @blind_t)
      create(:tournament_entry_member, tournament_entry: entry, user: angler)

      scope = ViewerScope.for(tournament: @blind_t, user: angler)
      assert_equal :own_entry_only, scope.visibility
      assert_equal entry.id, scope.entry_id
    end

    test "blind+active: entered organizer gets :own_entry_only (angler view)" do
      org_angler = create(:user, club: @club, role: :organizer)
      entry = create(:tournament_entry, tournament: @blind_t)
      create(:tournament_entry_member, tournament_entry: entry, user: org_angler)

      scope = ViewerScope.for(tournament: @blind_t, user: org_angler)
      assert_equal :own_entry_only, scope.visibility
      assert_equal entry.id, scope.entry_id
    end

    test "blind+active: non-entered organizer gets :full" do
      organizer = create(:user, club: @club, role: :organizer)

      scope = ViewerScope.for(tournament: @blind_t, user: organizer)
      assert_equal :full, scope.visibility
      assert_nil scope.entry_id
    end

    test "blind+active: non-entered, non-judge member gets :entries_only" do
      member = create(:user, club: @club, role: :member)

      scope = ViewerScope.for(tournament: @blind_t, user: member)
      assert_equal :entries_only, scope.visibility
      assert_nil scope.entry_id
    end
  end
end
