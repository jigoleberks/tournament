require "test_helper"

class Admin::CatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @member = create(:user, club: @club, name: "Club Carl", role: :member)
    @other_club = create(:club)
    @foreign = create(:user, club: @other_club, name: "Outsider Olive", role: :member)
    @member_catch = create(:catch, user: @member, length_inches: 22.5)
    @foreign_catch = create(:catch, user: @foreign, length_inches: 19.0)
  end

  test "non-organizer member is forbidden" do
    sign_in_as(@member)
    get admin_catches_path
    assert_response :forbidden
  end

  test "organizer sees the club's catches but not other clubs'" do
    sign_in_as(@organizer)
    get admin_catches_path
    assert_response :success
    assert_includes response.body, "Club Carl"
    refute_includes response.body, "Outsider Olive"
  end

  test "user_id filter scopes the catch list to the selected user" do
    other_member = create(:user, club: @club, name: "Other Member", role: :member)
    create(:catch, user: other_member, length_inches: 14.0)
    sign_in_as(@organizer)
    get admin_catches_path, params: { user_id: @member.id }

    assert_select "ul.grid li", minimum: 1 do
      assert_select "*", text: /Club Carl/
    end
    assert_select "ul.grid li *", text: /Other Member/, count: 0
  end

  test "organizer can update an in-club catch's length and species" do
    walleye = create(:species)
    sign_in_as(@organizer)
    assert_difference "JudgeAction.count", 1 do
      patch admin_catch_path(@member_catch.id), params: {
        species_id: walleye.id, length: "19.5", length_unit: "inches", note: "remeasured"
      }
    end
    assert_redirected_to admin_catch_path(@member_catch.id)
    @member_catch.reload
    assert_equal 19.5, @member_catch.length_inches.to_f
    assert_equal walleye.id, @member_catch.species_id
  end

  test "update snaps cm entry to the quarter grid and converts to inches" do
    sign_in_as(@organizer)
    # 50.1 cm snaps to 50.0 cm; 50.0 / 2.54 = 19.685...
    patch admin_catch_path(@member_catch.id), params: {
      length: "50.1", length_unit: "centimeters", note: "cm"
    }
    @member_catch.reload
    assert_equal "centimeters", @member_catch.length_unit
    assert_in_delta 19.685, @member_catch.length_inches.to_f, 0.01
  end

  test "update with an invalid length redirects with an alert instead of 500" do
    sign_in_as(@organizer)
    patch admin_catch_path(@member_catch.id), params: { length: "0", length_unit: "inches" }

    assert_redirected_to admin_catch_path(@member_catch.id)
    assert_not_nil flash[:alert]
    assert_equal 22.5, @member_catch.reload.length_inches.to_f, "invalid edit should not persist"
  end

  test "non-organizer cannot update" do
    sign_in_as(@member)
    patch admin_catch_path(@member_catch.id), params: { length: "10", length_unit: "inches" }
    assert_response :forbidden
  end

  test "organizer cannot update an out-of-club catch (404)" do
    sign_in_as(@organizer)
    patch admin_catch_path(@foreign_catch.id), params: { length: "10", length_unit: "inches" }
    assert_response :not_found
  end

  test "organizer sees the edit form on an in-club catch detail page" do
    sign_in_as(@organizer)
    get admin_catch_path(@member_catch.id)
    assert_response :success
    assert_select "select[name=species_id]"
    assert_select "input[name=length]"
    assert_includes response.body, "Club Carl"
  end

  test "edit form defaults the unit toggle to the catch's own logged unit, not the organizer's" do
    # @organizer prefers inches (factory default); the catch was logged in cm.
    # The form must seed from the catch's unit so an untouched length round-trips
    # instead of being re-snapped/flipped on a species- or note-only edit.
    @member_catch.update!(length_unit: "centimeters")
    sign_in_as(@organizer)
    get admin_catch_path(@member_catch.id)
    assert_select "input[name=length_unit][value=centimeters][checked=checked]"
    assert_select "input[name=length_unit][value=inches][checked=checked]", count: 0
  end

  test "detail page 404s for an out-of-club catch" do
    sign_in_as(@organizer)
    get admin_catch_path(@foreign_catch.id)
    assert_response :not_found
  end

  test "non-organizer cannot view a catch detail page" do
    sign_in_as(@member)
    get admin_catch_path(@member_catch.id)
    assert_response :forbidden
  end

  test "index links each catch to its detail page" do
    sign_in_as(@organizer)
    get admin_catches_path
    assert_select "a[href=?]", admin_catch_path(@member_catch.id)
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
