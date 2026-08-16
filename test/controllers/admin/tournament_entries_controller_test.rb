require "test_helper"

class Admin::TournamentEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @member = create(:user, club: @club, name: "Joe", role: :member)
    @team = create(:tournament, club: @club, mode: :team,
                                starts_at: 1.hour.from_now, ends_at: 3.hours.from_now)
    sign_in_as(@organizer)
  end

  test "non-organizer is forbidden" do
    sign_in_as(@member)
    post admin_tournament_tournament_entries_path(tournament_id: @team.id),
         params: { tournament_entry: { name: "Boat", member_user_ids: [@member.id] } }
    assert_response :forbidden
  end

  test "organizer creates a team entry" do
    assert_difference "TournamentEntry.count", 1 do
      post admin_tournament_tournament_entries_path(tournament_id: @team.id),
           params: { tournament_entry: { name: "Boat", member_user_ids: [@member.id] } }
    end
    entry = TournamentEntry.last
    assert_equal "Boat", entry.name
    assert_redirected_to edit_admin_tournament_path(@team)
  end

  test "organizer renames a team entry before tournament starts" do
    entry = create(:tournament_entry, tournament: @team, name: "Old")
    create(:tournament_entry_member, tournament_entry: entry, user: @member)

    patch admin_tournament_tournament_entry_path(tournament_id: @team.id, id: entry.id),
          params: { tournament_entry: { name: "New" } }

    assert_redirected_to edit_admin_tournament_path(@team)
    assert_equal "New", entry.reload.name
  end

  test "organizer renames an entry after tournament starts" do
    started = create(:tournament, club: @club, mode: :team, starts_at: 1.minute.ago, ends_at: 1.hour.from_now)
    entry = create(:tournament_entry, tournament: started, name: "Old")
    create(:tournament_entry_member, tournament_entry: entry, user: @member)
    patch admin_tournament_tournament_entry_path(tournament_id: started.id, id: entry.id),
          params: { tournament_entry: { name: "New" } }
    assert_redirected_to edit_admin_tournament_path(started)
    assert_equal "New", entry.reload.name
  end

  test "destroying an entry mid-tournament cascades placements and broadcasts the leaderboard" do
    walleye = create(:species, club: @club)
    started = create(:tournament, club: @club, mode: :team, starts_at: 30.minutes.ago, ends_at: 30.minutes.from_now)
    create(:scoring_slot, tournament: started, species: walleye, slot_count: 2)
    entry = create(:tournament_entry, tournament: started, name: "Doomed")
    create(:tournament_entry_member, tournament_entry: entry, user: @member)
    fish = create(:catch, user: @member, species: walleye, length_inches: 18, captured_at_device: 5.minutes.ago)
    Catches::PlaceInSlots.call(catch: fish)

    broadcast_calls = with_broadcast_spy do
      assert_difference "TournamentEntry.count", -1 do
        delete admin_tournament_tournament_entry_path(tournament_id: started.id, id: entry.id)
      end
    end
    assert_equal [started.id], broadcast_calls
    assert_equal 0, CatchPlacement.where(catch_id: fish.id).count
  end

  test "creating an entry backfills the user's in-window catches when the flag is on" do
    walleye = create(:species, name: "Walleye")
    tournament = create(:tournament, club: @club, starts_at: 4.hours.ago, ends_at: 1.hour.ago,
                                     backfill_late_entrants: true)
    create(:scoring_slot, tournament: tournament, species: walleye, slot_count: 2)
    member = create(:user, club: @club)
    missed = create(:catch, user: member, species: walleye,
                    length_inches: 20, captured_at_device: 3.hours.ago)

    post admin_tournament_tournament_entries_path(tournament_id: tournament.id),
         params: { tournament_entry: { member_user_ids: [member.id] } }

    assert_equal [missed.id],
                 CatchPlacement.where(tournament: tournament, active: true).pluck(:catch_id)
  end

  test "creating an entry stays forward-only when the flag is off" do
    walleye = create(:species, name: "Walleye")
    tournament = create(:tournament, club: @club, starts_at: 4.hours.ago, ends_at: 1.hour.ago)
    create(:scoring_slot, tournament: tournament, species: walleye, slot_count: 2)
    member = create(:user, club: @club)
    create(:catch, user: member, species: walleye,
           length_inches: 20, captured_at_device: 3.hours.ago)

    post admin_tournament_tournament_entries_path(tournament_id: tournament.id),
         params: { tournament_entry: { member_user_ids: [member.id] } }

    assert_empty CatchPlacement.where(tournament: tournament)
  end

  test "creating a team entry mirrors it into the linked tournament" do
    group = SecureRandom.uuid
    @team.update!(link_group_id: group)
    side = create(:tournament, club: @club, mode: :team, name: "Side",
                  starts_at: 1.hour.from_now, ends_at: 3.hours.from_now, link_group_id: group)

    assert_difference "TournamentEntry.count", 2 do
      post admin_tournament_tournament_entries_path(tournament_id: @team.id),
           params: { tournament_entry: { name: "Majestic Red", member_user_ids: [@member.id] } }
    end

    mirrored = side.tournament_entries.sole
    assert_equal "Majestic Red", mirrored.name
    assert_equal [@member], mirrored.users
  end

  test "removing a team entry removes it from the linked tournament" do
    group = SecureRandom.uuid
    @team.update!(link_group_id: group)
    side = create(:tournament, club: @club, mode: :team, name: "Side",
                  starts_at: 1.hour.from_now, ends_at: 3.hours.from_now, link_group_id: group)
    post admin_tournament_tournament_entries_path(tournament_id: @team.id),
         params: { tournament_entry: { name: "Majestic Red", member_user_ids: [@member.id] } }
    entry = @team.tournament_entries.sole

    assert_difference "TournamentEntry.count", -2 do
      delete admin_tournament_tournament_entry_path(tournament_id: @team.id, id: entry.id)
    end
    assert_empty side.tournament_entries.reload
  end

  test "renaming a team entry renames it in the linked tournament" do
    group = SecureRandom.uuid
    @team.update!(link_group_id: group)
    side = create(:tournament, club: @club, mode: :team, name: "Side",
                  starts_at: 1.hour.from_now, ends_at: 3.hours.from_now, link_group_id: group)
    post admin_tournament_tournament_entries_path(tournament_id: @team.id),
         params: { tournament_entry: { name: "Magestic Red", member_user_ids: [@member.id] } }
    entry = @team.tournament_entries.sole

    patch admin_tournament_tournament_entry_path(tournament_id: @team.id, id: entry.id),
          params: { tournament_entry: { name: "Majestic Red" } }

    assert_equal "Majestic Red", side.tournament_entries.sole.name
  end

  test "renaming an entry whose sync can't be mirrored redirects with an alert instead of crashing" do
    teammate = create(:user, club: @club, name: "Curtis", role: :member)
    group = SecureRandom.uuid
    @team.update!(link_group_id: group)
    side = create(:tournament, club: @club, mode: :team, name: "Side",
                  starts_at: 1.hour.from_now, ends_at: 3.hours.from_now, link_group_id: group)
    create(:tournament_judge, tournament: side, user: teammate)

    entry = create(:tournament_entry, tournament: @team, name: "Old Boat")
    create(:tournament_entry_member, tournament_entry: entry, user: @member)
    create(:tournament_entry_member, tournament_entry: entry, user: teammate)
    # The Side counterpart is missing teammate (a state that predates the
    # judge assignment, or just drifted) -- syncing the rename will try to
    # add teammate to it and trip user_not_a_judge.
    side_counterpart = create(:tournament_entry, tournament: side, name: "Old Boat")
    create(:tournament_entry_member, tournament_entry: side_counterpart, user: @member)

    assert_no_difference "TournamentEntryMember.count" do
      patch admin_tournament_tournament_entry_path(tournament_id: @team.id, id: entry.id),
            params: { tournament_entry: { name: "New Boat" } }
    end
    assert_redirected_to edit_admin_tournament_path(@team)
    assert_match(/judging/i, flash[:alert])
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
