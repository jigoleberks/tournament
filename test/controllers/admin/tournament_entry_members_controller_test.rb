require "test_helper"

class Admin::TournamentEntryMembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @a = create(:user, club: @club, name: "Aron", role: :member)
    @b = create(:user, club: @club, name: "Galen", role: :member)
    @team = create(:tournament, club: @club, mode: :team,
                                starts_at: 1.hour.from_now, ends_at: 3.hours.from_now)
    @entry = create(:tournament_entry, tournament: @team, name: "Boat 1")
    create(:tournament_entry_member, tournament_entry: @entry, user: @a)
    sign_in_as(@organizer)
  end

  test "non-organizer members are forbidden" do
    sign_in_as(@a)
    post admin_tournament_tournament_entry_tournament_entry_members_path(
      tournament_id: @team.id, tournament_entry_id: @entry.id), params: { user_id: @b.id }
    assert_response :forbidden
  end

  test "organizer adds a member to a team entry before tournament starts" do
    assert_difference "TournamentEntryMember.count", 1 do
      post admin_tournament_tournament_entry_tournament_entry_members_path(
        tournament_id: @team.id, tournament_entry_id: @entry.id), params: { user_id: @b.id }
    end
    assert_redirected_to edit_admin_tournament_path(@team)
    assert_match(/Added Galen/, flash[:notice])
  end

  test "organizer removes a member from a team entry before tournament starts" do
    create(:tournament_entry_member, tournament_entry: @entry, user: @b)
    member = TournamentEntryMember.find_by(tournament_entry_id: @entry.id, user_id: @b.id)

    assert_difference "TournamentEntryMember.count", -1 do
      delete admin_tournament_tournament_entry_tournament_entry_member_path(
        tournament_id: @team.id, tournament_entry_id: @entry.id, id: member.id)
    end
    assert_redirected_to edit_admin_tournament_path(@team)
  end

  test "organizer adds a member to a team entry after tournament starts" do
    @team.update!(starts_at: 1.minute.ago, ends_at: 1.hour.from_now)
    assert_difference "TournamentEntryMember.count", 1 do
      post admin_tournament_tournament_entry_tournament_entry_members_path(
        tournament_id: @team.id, tournament_entry_id: @entry.id), params: { user_id: @b.id }
    end
    assert_redirected_to edit_admin_tournament_path(@team)
  end

  test "add rejects user from another club" do
    other_club = create(:club)
    foreigner = create(:user, club: other_club)
    assert_no_difference "TournamentEntryMember.count" do
      post admin_tournament_tournament_entry_tournament_entry_members_path(
        tournament_id: @team.id, tournament_entry_id: @entry.id), params: { user_id: foreigner.id }
    end
    assert_match(/not found/i, flash[:alert])
  end

  test "add is rejected on solo tournaments" do
    solo = create(:tournament, club: @club, mode: :solo,
                               starts_at: 1.hour.from_now, ends_at: 3.hours.from_now)
    solo_entry = create(:tournament_entry, tournament: solo)
    create(:tournament_entry_member, tournament_entry: solo_entry, user: @a)
    assert_no_difference "TournamentEntryMember.count" do
      post admin_tournament_tournament_entry_tournament_entry_members_path(
        tournament_id: solo.id, tournament_entry_id: solo_entry.id), params: { user_id: @b.id }
    end
    assert_match(/Solo entries can't have additional members/i, flash[:alert])
  end

  test "adding a member backfills their in-window catches when the flag is on" do
    walleye = create(:species, name: "Walleye")
    @team.update!(starts_at: 4.hours.ago, ends_at: 1.hour.ago, backfill_late_entrants: true)
    create(:scoring_slot, tournament: @team, species: walleye, slot_count: 2)
    missed = create(:catch, user: @b, species: walleye,
                    length_inches: 20, captured_at_device: 3.hours.ago)

    post admin_tournament_tournament_entry_tournament_entry_members_path(
      tournament_id: @team.id, tournament_entry_id: @entry.id), params: { user_id: @b.id }

    assert_equal [missed.id],
                 CatchPlacement.where(tournament: @team, active: true).pluck(:catch_id)
  end

  test "adding a member stays forward-only when the flag is off" do
    walleye = create(:species, name: "Walleye")
    @team.update!(starts_at: 4.hours.ago, ends_at: 1.hour.ago)
    create(:scoring_slot, tournament: @team, species: walleye, slot_count: 2)
    create(:catch, user: @b, species: walleye,
           length_inches: 20, captured_at_device: 3.hours.ago)

    post admin_tournament_tournament_entry_tournament_entry_members_path(
      tournament_id: @team.id, tournament_entry_id: @entry.id), params: { user_id: @b.id }

    assert_empty CatchPlacement.where(tournament: @team)
  end

  test "same_as_last_week adds last week's crew to tonight's entry" do
    # Fresh users, not @a/@b — @a is already seated in @entry ("Boat 1") in
    # @team via setup, so reusing it here would trip the one-entry-per-user
    # validation on the second entry rather than exercising the happy path.
    galen = create(:user, club: @club, name: "Galen Patterson")
    troy = create(:user, club: @club, name: "Troy Patterson")
    boat = create(:boat, club: @club, name: "Team Patterson", captain: galen)
    last_week = create(:tournament, club: @club, mode: :team,
                       starts_at: 8.days.ago, ends_at: 8.days.ago + 3.hours)
    old_entry = create(:tournament_entry, tournament: last_week, name: "Team Patterson", boat: boat)
    create(:tournament_entry_member, tournament_entry: old_entry, user: galen)
    create(:tournament_entry_member, tournament_entry: old_entry, user: troy)

    tonight_entry = create(:tournament_entry, tournament: @team, name: "Team Patterson", boat: boat)

    assert_difference "TournamentEntryMember.count", 2 do
      post same_as_last_week_admin_tournament_tournament_entry_tournament_entry_members_path(
        tournament_id: @team.id, tournament_entry_id: tonight_entry.id)
    end
    assert_redirected_to edit_admin_tournament_path(@team)
    assert_match(/Added 2 from last time/, flash[:notice])
    assert_equal [galen, troy].sort_by(&:id), tonight_entry.reload.users.sort_by(&:id)
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
