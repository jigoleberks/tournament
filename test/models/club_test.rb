require "test_helper"

class ClubTest < ActiveSupport::TestCase
  test "name is required" do
    assert_not Club.new.valid?
  end

  test "name must be unique" do
    create(:club, name: "Test Fishing Club")
    duplicate = build(:club, name: "Test Fishing Club")
    assert_not duplicate.valid?
  end

  test "active_rules_season defaults to open_water" do
    club = create(:club)
    assert club.active_rules_season_open_water?
  end

  test "current_rules_revision returns the latest revision for the active season" do
    club = create(:club)
    user = create(:user, club: club)
    create(:club_rules_revision, club: club, edited_by_user: user, season: :open_water,
                                 body: "old", created_at: 2.days.ago)
    newer = create(:club_rules_revision, club: club, edited_by_user: user, season: :open_water,
                                         body: "new", created_at: 1.day.ago)

    assert_equal newer, club.current_rules_revision
  end

  test "current_rules_revision returns nil when active season has no revisions" do
    club = create(:club)
    assert_nil club.current_rules_revision
  end

  test "current_rules_revision tracks active_rules_season changes" do
    club = create(:club)
    user = create(:user, club: club)
    ow_rev  = create(:club_rules_revision, club: club, edited_by_user: user, season: :open_water)
    ice_rev = create(:club_rules_revision, club: club, edited_by_user: user, season: :ice)

    assert_equal ow_rev, club.current_rules_revision
    club.update!(active_rules_season: :ice)
    assert_equal ice_rev, club.current_rules_revision
  end

  test "banner_message defaults to nil and banner_style defaults to info" do
    club = Club.create!(name: "Banner Defaults FC")
    assert_nil club.banner_message
    assert_equal "info", club.banner_style
  end

  test "banner_style maps to integers good=1 alert=2" do
    club = Club.create!(name: "Banner Enum FC")
    club.update!(banner_style: :alert)
    raw = Club.connection.select_value(Club.where(id: club.id).select(:banner_style).to_sql)
    assert_equal 2, raw
  end

  test "new club gets the default season points settings" do
    club = create(:club)
    assert_equal "tiered_ladders", club.season_points_scheme
    assert_equal 0.5, club.season_points_attendance.to_f
    assert_equal 3, club.season_points_min_entries
    assert_equal [[3, 2, 1], [6, 4, 2], [9, 6, 3], [9, 6, 3]], club.season_points_ladders
    assert_equal [3, 2, 1], club.season_points_base_ladder
    assert_equal [1, 2, 3, 3], club.season_points_tier_multipliers
  end

  test "rejects a ladder whose amounts increase" do
    club = create(:club)
    club.season_points_ladders = [[3, 2, 1], [2, 4, 6], [9, 6, 3], [9, 6, 3]]
    assert_not club.valid?
    assert_includes club.errors[:season_points_ladders].join, "highest first"
  end

  test "allows equal adjacent amounts in a ladder" do
    club = create(:club)
    club.season_points_ladders = [[3, 3, 1], [6, 4, 2], [9, 6, 3], [9, 6, 3]]
    assert club.valid?, club.errors.full_messages.join(", ")
  end

  test "rejects negative amounts, empty ladders, and wrong band counts" do
    club = create(:club)

    club.season_points_ladders = [[3, 2, -1], [6, 4, 2], [9, 6, 3], [9, 6, 3]]
    assert_not club.valid?

    club.season_points_ladders = [[], [6, 4, 2], [9, 6, 3], [9, 6, 3]]
    assert_not club.valid?

    club.season_points_ladders = [[3, 2, 1], [6, 4, 2]]
    assert_not club.valid?
  end

  test "rejects a non-positive multiplier, a negative attendance, and min entries below 1" do
    club = create(:club)

    club.season_points_tier_multipliers = [1, 0, 3, 3]
    assert_not club.valid?

    club = create(:club)
    club.season_points_attendance = -1
    assert_not club.valid?

    club = create(:club)
    club.season_points_min_entries = 0
    assert_not club.valid?
  end

  test "ladder text writers parse comma-separated strings" do
    club = create(:club)
    club.season_points_ladders_text = ["10, 8, 6, 5", "12,10,8", "14, 12, 10", "16,14,12"]
    club.season_points_base_ladder_text = "5, 4, 3"
    club.season_points_tier_multipliers_text = "1, 1.5, 2, 2.5"
    assert club.valid?, club.errors.full_messages.join(", ")
    assert_equal [10.0, 8.0, 6.0, 5.0], club.season_points_ladders.first
    assert_equal [5.0, 4.0, 3.0], club.season_points_base_ladder
    assert_equal [1.0, 1.5, 2.0, 2.5], club.season_points_tier_multipliers
  end

  test "a junk token in a ladder text field is a validation error, not an exception" do
    club = create(:club)
    club.season_points_ladders_text = ["10, eight, 6", "6,4,2", "9,6,3", "9,6,3"]
    assert_not club.valid?
    assert_includes club.errors[:season_points_ladders].join, "numbers"
  end

  test "ladder text round-trips through season_points_ladder_text" do
    club = create(:club)
    club.season_points_ladders_text = ["10, 8, 6", "6,4,2", "9,6,3", "9,6,3"]
    assert_equal "10, 8, 6", club.season_points_ladder_text(0)
  end
end
