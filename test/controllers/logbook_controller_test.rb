require "test_helper"

class LogbookControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @walleye = create(:species, club: @club, name: "Walleye")
    @original_logbook_enabled = ENV["LOGBOOK_ENABLED"]
    sign_in_as(@user)
  end

  teardown do
    if @original_logbook_enabled.nil?
      ENV.delete("LOGBOOK_ENABLED")
    else
      ENV["LOGBOOK_ENABLED"] = @original_logbook_enabled
    end
  end

  test "GET /logbook renders when enabled" do
    ENV["LOGBOOK_ENABLED"] = "true"
    get logbook_path
    assert_response :success
    assert_includes @response.body, "Logbook"
  end

  test "GET /logbook redirects to root when disabled" do
    ENV.delete("LOGBOOK_ENABLED")
    get logbook_path
    assert_redirected_to root_path
    follow_redirect!
    assert_match(/isn't enabled/i, flash[:alert] || @response.body)
  end

  test "GET /logbook lists the user's catches only" do
    ENV["LOGBOOK_ENABLED"] = "true"
    own = create(:catch, user: @user, species: @walleye, length_inches: 18.0)
    other = create(:user, club: @club)
    create(:catch, user: other, species: @walleye, length_inches: 22.0)
    get logbook_path
    assert_response :success
    assert_select "a[href=?]", catch_path(own)
  end

  test "GET /logbook filters by structure" do
    ENV["LOGBOOK_ENABLED"] = "true"
    a = create(:catch, user: @user, species: @walleye, structure: :hump)
    b = create(:catch, user: @user, species: @walleye, structure: :flat)
    get logbook_path, params: { structure: "hump" }
    assert_response :success
    assert_select "a[href=?]", catch_path(a)
    assert_select "a[href=?]", catch_path(b), count: 0
  end

  test "GET /logbook filters by bait" do
    ENV["LOGBOOK_ENABLED"] = "true"
    bait = create(:bait, user: @user)
    matched = create(:catch, user: @user, species: @walleye, bait: bait)
    unmatched = create(:catch, user: @user, species: @walleye)
    get logbook_path, params: { bait_id: bait.id }
    assert_response :success
    assert_select "a[href=?]", catch_path(matched)
    assert_select "a[href=?]", catch_path(unmatched), count: 0
  end

  test "GET /logbook ignores an invalid structure key" do
    ENV["LOGBOOK_ENABLED"] = "true"
    a = create(:catch, user: @user, species: @walleye, structure: :hump)
    get logbook_path, params: { structure: "not-a-structure" }
    assert_response :success
    assert_select "a[href=?]", catch_path(a)
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
