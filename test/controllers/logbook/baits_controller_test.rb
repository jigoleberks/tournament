require "test_helper"

class Logbook::BaitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @other = create(:user, club: @club)
    @original_logbook_enabled = ENV["LOGBOOK_ENABLED"]
    ENV["LOGBOOK_ENABLED"] = "true"
    sign_in_as(@user)
  end

  teardown do
    if @original_logbook_enabled.nil?
      ENV.delete("LOGBOOK_ENABLED")
    else
      ENV["LOGBOOK_ENABLED"] = @original_logbook_enabled
    end
  end

  test "GET /logbook/baits lists the user's active baits" do
    mine = create(:bait, user: @user, color: "mine-color")
    archived = create(:bait, user: @user, color: "archived-color", archived_at: Time.current)
    theirs = create(:bait, user: @other, color: "others-color")
    get logbook_baits_path
    assert_response :success
    assert_includes @response.body, mine.display_name
    assert_includes @response.body, archived.display_name
    assert_not_includes @response.body, theirs.display_name
  end

  test "POST /logbook/baits creates a bait" do
    assert_difference -> { Bait.count } => 1 do
      post logbook_baits_path, params: {
        bait: { color: "chartreuse", weight: "1/4 oz", lure_type: "jighead", bait_type: "minnow" }
      }
    end
    bait = Bait.last
    assert_equal @user, bait.user
    assert_equal "chartreuse", bait.color
    assert_redirected_to logbook_baits_path
  end

  test "POST /logbook/baits rejects an empty bait" do
    assert_no_difference -> { Bait.count } do
      post logbook_baits_path, params: { bait: { color: "", weight: "", lure_type: "", bait_type: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "POST /logbook/baits persists the plastic and its colour" do
    assert_difference -> { Bait.count } => 1 do
      post logbook_baits_path, params: {
        bait: { weight: "1/4 oz", lure_type: "jighead", plastic: "tube jig", plastic_color: "pink" }
      }
    end
    bait = Bait.last
    assert_equal "tube jig", bait.plastic
    assert_equal "pink", bait.plastic_color
    assert_redirected_to logbook_baits_path
  end

  test "PATCH /logbook/baits/:id updates the bait" do
    bait = create(:bait, user: @user, color: "orange")
    patch logbook_bait_path(bait), params: { bait: { color: "blue" } }
    assert_redirected_to logbook_baits_path
    assert_equal "blue", bait.reload.color
  end

  test "PATCH /logbook/baits/:id 404s for another user's bait" do
    bait = create(:bait, user: @other, color: "before")
    patch logbook_bait_path(bait), params: { bait: { color: "after" } }
    assert_response :not_found
    assert_equal "before", bait.reload.color
  end

  test "DELETE /logbook/baits/:id archives, does not destroy" do
    bait = create(:bait, user: @user)
    assert_no_difference -> { Bait.count } do
      delete logbook_bait_path(bait)
    end
    assert bait.reload.archived?
    assert_redirected_to logbook_baits_path
  end

  test "DELETE /logbook/baits/:id 404s for another user's bait" do
    bait = create(:bait, user: @other)
    delete logbook_bait_path(bait)
    assert_response :not_found
    assert_not bait.reload.archived?
  end

  test "redirects to root when logbook is disabled" do
    ENV.delete("LOGBOOK_ENABLED")
    get logbook_baits_path
    assert_redirected_to root_path
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
