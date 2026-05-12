require "test_helper"

class Admin::Clubs::TournamentTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host_club    = create(:club, name: "Host Anglers")
    @foreign_club = create(:club, name: "Northtown Anglers")
    @admin     = create(:user, club: @host_club, admin: true, role: :organizer)
    @member    = create(:user, club: @host_club, role: :member)

    @foreign_template = create(:tournament_template, club: @foreign_club, name: "Northtown Weekly")
    @host_template    = create(:tournament_template, club: @host_club, name: "Host Weekly")
  end

  test "non-admin forbidden on index" do
    sign_in_as(@member)
    get admin_club_tournament_templates_path(@foreign_club)
    assert_response :forbidden
  end

  test "admin sees foreign templates, not host ones" do
    sign_in_as(@admin)
    get admin_club_tournament_templates_path(@foreign_club)
    assert_response :success
    assert_includes response.body, "Northtown Weekly"
    refute_includes response.body, "Host Weekly"
  end

  test "admin can view a foreign template's show page" do
    sign_in_as(@admin)
    get admin_club_tournament_template_path(@foreign_club, @foreign_template)
    assert_response :success
    assert_includes response.body, "Northtown Weekly"
  end

  test "show 404s for a template that belongs to another club" do
    sign_in_as(@admin)
    get admin_club_tournament_template_path(@foreign_club, @host_template)
    assert_response :not_found
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
