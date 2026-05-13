require "test_helper"

class Admin::Clubs::RulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host_club    = create(:club, name: "Host Anglers")
    @foreign_club = create(:club, name: "Northtown Anglers")
    @admin     = create(:user, club: @host_club, admin: true, role: :organizer)
    @member    = create(:user, club: @host_club, role: :member)

    @foreign_rev = create(:club_rules_revision,
                          club: @foreign_club,
                          season: :open_water,
                          edited_by_user: create(:user, club: @foreign_club, name: "Foreign Editor"),
                          body: "<h1>Northtown rules</h1>")
    @host_rev    = create(:club_rules_revision,
                          club: @host_club,
                          season: :open_water,
                          edited_by_user: @admin,
                          body: "<h1>Host rules</h1>")
  end

  test "non-admin forbidden on index" do
    sign_in_as(@member)
    get admin_club_rules_path(@foreign_club)
    assert_response :forbidden
  end

  test "admin sees foreign club rules on index" do
    sign_in_as(@admin)
    get admin_club_rules_path(@foreign_club)
    assert_response :success
    assert_includes response.body, "Northtown rules"
    refute_includes response.body, "Host rules"
  end

  test "history lists only this club's revisions" do
    sign_in_as(@admin)
    get history_admin_club_rules_path(@foreign_club), params: { season: "open_water" }
    assert_response :success
    assert_includes response.body, "Foreign Editor"
  end

  test "show renders a specific revision" do
    sign_in_as(@admin)
    get admin_club_rule_path(@foreign_club, @foreign_rev)
    assert_response :success
    assert_includes response.body, "Northtown rules"
  end

  test "show 404s for a revision belonging to another club" do
    sign_in_as(@admin)
    get admin_club_rule_path(@foreign_club, @host_rev)
    assert_response :not_found
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
