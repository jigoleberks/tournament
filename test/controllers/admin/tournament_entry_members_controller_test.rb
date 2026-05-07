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

  test "add is locked once tournament has started" do
    @team.update!(starts_at: 1.minute.ago, ends_at: 1.hour.from_now)
    assert_no_difference "TournamentEntryMember.count" do
      post admin_tournament_tournament_entry_tournament_entry_members_path(
        tournament_id: @team.id, tournament_entry_id: @entry.id), params: { user_id: @b.id }
    end
    assert_match(/locked/i, flash[:alert])
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

  test "add is locked on solo tournaments" do
    solo = create(:tournament, club: @club, mode: :solo,
                               starts_at: 1.hour.from_now, ends_at: 3.hours.from_now)
    solo_entry = create(:tournament_entry, tournament: solo)
    create(:tournament_entry_member, tournament_entry: solo_entry, user: @a)
    assert_no_difference "TournamentEntryMember.count" do
      post admin_tournament_tournament_entry_tournament_entry_members_path(
        tournament_id: solo.id, tournament_entry_id: solo_entry.id), params: { user_id: @b.id }
    end
    assert_match(/locked/i, flash[:alert])
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
