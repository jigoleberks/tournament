require "test_helper"

class Organizers::TournamentDeputiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club      = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @member    = create(:user, club: @club, role: :member, name: "Mike")
    @upcoming  = create(:tournament, club: @club, starts_at: 1.hour.from_now, ends_at: 3.hours.from_now)
  end

  test "plain members are forbidden" do
    sign_in_as(@member)
    post organizers_tournament_tournament_deputies_path(tournament_id: @upcoming.id),
         params: { tournament_deputy: { user_id: @member.id } }
    assert_response :forbidden
  end

  test "an organizer adds a deputy and is recorded as the granter" do
    sign_in_as(@organizer)
    assert_difference "TournamentDeputy.count", 1 do
      post organizers_tournament_tournament_deputies_path(tournament_id: @upcoming.id),
           params: { tournament_deputy: { user_id: @member.id } }
    end
    assert_redirected_to edit_organizers_tournament_path(@upcoming)
    deputy = TournamentDeputy.find_by(tournament: @upcoming, user: @member)
    assert_equal @organizer, deputy.granted_by_user
  end

  test "an organizer removes a deputy" do
    sign_in_as(@organizer)
    d = create(:tournament_deputy, tournament: @upcoming, user: @member, granted_by_user: @organizer)
    assert_difference "TournamentDeputy.count", -1 do
      delete organizers_tournament_tournament_deputy_path(tournament_id: @upcoming.id, id: d.id)
    end
    assert_redirected_to edit_organizers_tournament_path(@upcoming)
  end

  test "a live deputy cannot deputize anyone else" do
    create(:tournament_deputy, tournament: @upcoming, user: @member, granted_by_user: @organizer)
    victim = create(:user, club: @club, role: :member)
    sign_in_as(@member)
    post organizers_tournament_tournament_deputies_path(tournament_id: @upcoming.id),
         params: { tournament_deputy: { user_id: victim.id } }
    assert_response :forbidden
  end

  test "a live deputy CAN manage tournament entries" do
    create(:tournament_deputy, tournament: @upcoming, user: @member, granted_by_user: @organizer)
    sign_in_as(@member)
    assert_difference "TournamentEntry.count", 1 do
      post organizers_tournament_tournament_entries_path(tournament_id: @upcoming.id),
           params: { tournament_entry: { member_user_ids: [@member.id] } }
    end
  end

  test "an expired deputy cannot manage tournament entries" do
    started = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:tournament_deputy, tournament: started, user: @member, granted_by_user: @organizer)
    sign_in_as(@member)
    post organizers_tournament_tournament_entries_path(tournament_id: started.id),
         params: { tournament_entry: { member_user_ids: [@member.id] } }
    assert_response :forbidden
  end

  test "a missing user_id redirects with an alert" do
    sign_in_as(@organizer)
    post organizers_tournament_tournament_deputies_path(tournament_id: @upcoming.id),
         params: { tournament_deputy: { user_id: "" } }
    assert_redirected_to edit_organizers_tournament_path(@upcoming)
    assert_equal "Pick a member first.", flash[:alert]
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
