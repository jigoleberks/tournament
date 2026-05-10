require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "redirects to sign in when not signed in" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "renders home when signed in" do
    user = create(:user, name: "Joe")
    post session_path, params: { email: user.email }
    token = SignInToken.last
    get consume_session_path(token: token.token)
    get root_path
    assert_response :success
    assert_select "h1", ENV.fetch("APP_NAME", "Tournament")
    assert_match "Joe", response.body
  end

  test "notifications Enable button defaults to non-blue (JS swaps it on when subscribed)" do
    user = create(:user)
    post session_path, params: { email: user.email }
    get consume_session_path(token: SignInToken.last.token)
    get root_path
    assert_response :success
    assert_select "button[data-action~=?]", "push-register#enable" do |btns|
      assert_not btns.first["class"].to_s.include?("bg-blue"),
                 "Enable button should default to non-blue; the JS controller flips it to blue when the subscription is active"
    end
  end

  test "deactivated user with an existing session is signed out on next request" do
    user = create(:user)
    post session_path, params: { email: user.email }
    get consume_session_path(token: SignInToken.last.token)
    assert_equal user.id, session[:user_id]

    user.update!(deactivated_at: Time.current)
    get root_path
    assert_redirected_to new_session_path
    assert_nil session[:user_id]
  end

  test "home page hides Rules button when no revision exists for active season" do
    sign_in_as(@member)
    get root_path
    assert_response :success
    assert_no_match %r{Rules \(}, response.body
  end

  test "home page shows Rules button with date when active-season revision exists" do
    rev = create(:club_rules_revision, club: @club, edited_by_user: @organizer,
                                       season: :open_water, body: "<div>x</div>",
                                       created_at: Time.zone.local(2026, 5, 9, 10))
    sign_in_as(@member)
    get root_path
    assert_response :success
    assert_match "Rules (May 9, 2026)", response.body
    assert_match rules_path, response.body
  end

  test "home Rules button reflects active season change" do
    create(:club_rules_revision, club: @club, edited_by_user: @organizer,
                                 season: :open_water, body: "<div>ow</div>",
                                 created_at: Time.zone.local(2026, 5, 9, 10))
    ice_rev = create(:club_rules_revision, club: @club, edited_by_user: @organizer,
                                           season: :ice, body: "<div>ice</div>",
                                           created_at: Time.zone.local(2026, 1, 1, 10))
    @club.update!(active_rules_season: :ice)
    sign_in_as(@member)
    get root_path
    assert_match "Rules (Jan 1, 2026)", response.body
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end

  def setup
    @club = create(:club)
    @member = create(:user, club: @club, role: :member)
    @organizer = create(:user, club: @club, role: :organizer)
  end
end
