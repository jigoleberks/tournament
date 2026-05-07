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

  test "rename is locked once tournament has started" do
    started = create(:tournament, club: @club, mode: :team, starts_at: 1.minute.ago, ends_at: 1.hour.from_now)
    entry = create(:tournament_entry, tournament: started, name: "Locked")
    create(:tournament_entry_member, tournament_entry: entry, user: @member)
    patch admin_tournament_tournament_entry_path(tournament_id: started.id, id: entry.id),
          params: { tournament_entry: { name: "Try" } }
    assert_match(/started/i, flash[:alert])
    assert_equal "Locked", entry.reload.name
  end

  test "destroy is locked once tournament has started" do
    started = create(:tournament, club: @club, mode: :team, starts_at: 1.minute.ago, ends_at: 1.hour.from_now)
    entry = create(:tournament_entry, tournament: started)
    create(:tournament_entry_member, tournament_entry: entry, user: @member)
    assert_no_difference "TournamentEntry.count" do
      delete admin_tournament_tournament_entry_path(tournament_id: started.id, id: entry.id)
    end
    assert_match(/started/i, flash[:alert])
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
