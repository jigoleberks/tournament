require "test_helper"

class Organizers::TournamentEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @member = create(:user, club: @club, name: "Joe", role: :member)
    @teammate = create(:user, club: @club, name: "Curtis", role: :member)
    @solo = create(:tournament, club: @club, mode: :solo)
    @team = create(:tournament, club: @club, mode: :team)
    sign_in_as(@organizer)
  end

  test "members are forbidden" do
    sign_in_as(@member)
    post organizers_tournament_tournament_entries_path(tournament_id: @solo.id),
         params: { tournament_entry: { member_user_ids: [@member.id] } }
    assert_response :forbidden
  end

  test "organizer creates a solo entry for one user" do
    assert_difference "TournamentEntry.count", 1 do
      post organizers_tournament_tournament_entries_path(tournament_id: @solo.id),
           params: { tournament_entry: { member_user_ids: [@member.id] } }
    end
    entry = TournamentEntry.last
    assert_equal [@member], entry.users
    assert_redirected_to edit_organizers_tournament_path(@solo)
  end

  test "organizer creates a team entry with two members and a boat name" do
    assert_difference "TournamentEntry.count", 1 do
      post organizers_tournament_tournament_entries_path(tournament_id: @team.id),
           params: { tournament_entry: { name: "Curtis's Boat", member_user_ids: [@member.id, @teammate.id] } }
    end
    entry = TournamentEntry.last
    assert_equal "Curtis's Boat", entry.name
    assert_equal [@member, @teammate].sort_by(&:id), entry.users.sort_by(&:id)
  end

  test "deactivated members can't be added to a new entry" do
    @member.update!(deactivated_at: Time.current)
    assert_no_difference "TournamentEntry.count" do
      post organizers_tournament_tournament_entries_path(tournament_id: @solo.id),
           params: { tournament_entry: { member_user_ids: [@member.id] } }
    end
    assert_match(/unavailable/i, flash[:alert])
  end

  test "organizer destroys an entry" do
    entry = create(:tournament_entry, tournament: @solo)
    create(:tournament_entry_member, tournament_entry: entry, user: @member)

    assert_difference "TournamentEntry.count", -1 do
      delete organizers_tournament_tournament_entry_path(tournament_id: @solo.id, id: entry.id)
    end
    assert_redirected_to edit_organizers_tournament_path(@solo)
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
