require "test_helper"

class Organizers::TournamentJudgesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @member = create(:user, club: @club, name: "Mike", role: :member)
    @tournament = create(:tournament, club: @club)
    sign_in_as(@organizer)
  end

  test "members are forbidden" do
    sign_in_as(@member)
    post organizers_tournament_tournament_judges_path(tournament_id: @tournament.id),
         params: { tournament_judge: { user_id: @member.id } }
    assert_response :forbidden
  end

  test "organizer adds a judge" do
    assert_difference "TournamentJudge.count", 1 do
      post organizers_tournament_tournament_judges_path(tournament_id: @tournament.id),
           params: { tournament_judge: { user_id: @member.id } }
    end
    assert_redirected_to edit_organizers_tournament_path(@tournament)
    assert TournamentJudge.exists?(tournament: @tournament, user: @member)
  end

  test "organizer removes a judge" do
    tj = create(:tournament_judge, tournament: @tournament, user: @member)
    assert_difference "TournamentJudge.count", -1 do
      delete organizers_tournament_tournament_judge_path(tournament_id: @tournament.id, id: tj.id)
    end
    assert_redirected_to edit_organizers_tournament_path(@tournament)
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
