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
end
