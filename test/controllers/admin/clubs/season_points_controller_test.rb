require "test_helper"

class Admin::Clubs::SeasonPointsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @home_club = create(:club, name: "Admin Home FC")
    @admin     = create(:user, club: @home_club, admin: true)
    @organizer = create(:user, club: @home_club, role: :organizer)

    @target_club = create(:club, name: "Target FC")
  end

  test "a club organizer without the site-admin flag is forbidden" do
    sign_in_as(@organizer)
    get edit_admin_club_season_points_path(@target_club)
    assert_response :forbidden
  end

  test "admin sees the editor with the current settings and a preview" do
    sign_in_as(@admin)
    get edit_admin_club_season_points_path(@target_club)
    assert_response :success
    assert_includes response.body, "Season points"
    assert_includes response.body, "9, 6, 3"
  end

  test "update saves the scheme, amounts, and ladders" do
    sign_in_as(@admin)
    patch admin_club_season_points_path(@target_club), params: {
      club: {
        season_points_scheme: "full_field",
        season_points_attendance: "1.0",
        season_points_min_entries: "4",
        season_points_ladders_text: ["10, 8, 6", "12, 10, 8", "14, 12, 10", "16, 14, 12"],
        season_points_base_ladder_text: "5, 4, 3",
        season_points_tier_multipliers_text: "1, 1.5, 2, 2.5"
      }
    }
    assert_redirected_to admin_club_path(@target_club)

    @target_club.reload
    assert_equal "full_field", @target_club.season_points_scheme
    assert_equal 1.0, @target_club.season_points_attendance.to_f
    assert_equal 4, @target_club.season_points_min_entries
    assert_equal [10.0, 8.0, 6.0], @target_club.season_points_ladders.first
    assert_equal [5.0, 4.0, 3.0], @target_club.season_points_base_ladder
    assert_equal [1.0, 1.5, 2.0, 2.5], @target_club.season_points_tier_multipliers
  end

  test "invalid input re-renders the form as 422 and changes nothing" do
    sign_in_as(@admin)
    patch admin_club_season_points_path(@target_club), params: {
      club: {
        season_points_scheme: "tiered_ladders",
        season_points_attendance: "0.5",
        season_points_min_entries: "3",
        season_points_ladders_text: ["1, 2, 3", "6, 4, 2", "9, 6, 3", "9, 6, 3"],
        season_points_base_ladder_text: "3, 2, 1",
        season_points_tier_multipliers_text: "1, 2, 3, 3"
      }
    }
    assert_response :unprocessable_entity
    assert_equal [[3, 2, 1], [6, 4, 2], [9, 6, 3], [9, 6, 3]], @target_club.reload.season_points_ladders
  end

  test "an out-of-range scheme is a 422, not a 500" do
    sign_in_as(@admin)
    patch admin_club_season_points_path(@target_club), params: {
      club: {
        season_points_scheme: "nonsense",
        season_points_attendance: "0.5",
        season_points_min_entries: "3",
        season_points_ladders_text: ["3, 2, 1", "6, 4, 2", "9, 6, 3", "9, 6, 3"],
        season_points_base_ladder_text: "3, 2, 1",
        season_points_tier_multipliers_text: "1, 2, 3, 3"
      }
    }
    assert_response :unprocessable_entity
    assert_equal "tiered_ladders", @target_club.reload.season_points_scheme
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
