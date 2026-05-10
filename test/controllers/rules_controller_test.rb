require "test_helper"

class RulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @member = create(:user, club: @club, role: :member)
    @organizer = create(:user, club: @club, role: :organizer)
  end

  test "redirects unauthenticated requests to sign-in" do
    get rules_path
    assert_redirected_to new_session_path
  end

  test "shows the active season's latest revision body" do
    create(:club_rules_revision, club: @club, edited_by_user: @organizer,
                                 season: :open_water, body: "# Open water\n\n- No live bait")
    sign_in_as(@member)
    get rules_path
    assert_response :success
    assert_match "Open water", response.body
    assert_match "No live bait", response.body
  end

  test "shows empty-state when no revision exists for active season" do
    sign_in_as(@member)
    get rules_path
    assert_response :success
    assert_match "No rules published yet.", response.body
  end

  test "shows the editor name only for organizer viewers" do
    create(:club_rules_revision, club: @club, edited_by_user: @organizer,
                                 season: :open_water, body: "rules")
    sign_in_as(@organizer)
    get rules_path
    assert_match @organizer.name, response.body

    sign_in_as(@member)
    get rules_path
    assert_no_match @organizer.name, response.body
  end

  test "switches to ice revision when active_rules_season is ice" do
    create(:club_rules_revision, club: @club, edited_by_user: @organizer,
                                 season: :open_water, body: "OPEN WATER BODY")
    create(:club_rules_revision, club: @club, edited_by_user: @organizer,
                                 season: :ice, body: "ICE BODY")
    @club.update!(active_rules_season: :ice)
    sign_in_as(@member)

    get rules_path
    assert_match "ICE BODY", response.body
    assert_no_match "OPEN WATER BODY", response.body
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
