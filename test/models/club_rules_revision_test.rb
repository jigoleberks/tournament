require "test_helper"

class ClubRulesRevisionTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
  end

  test "is valid with body, season, edited_by_user, and club" do
    rev = build(:club_rules_revision, club: @club, edited_by_user: @user)
    assert rev.valid?, rev.errors.full_messages.inspect
  end

  test "requires body" do
    rev = build(:club_rules_revision, club: @club, edited_by_user: @user, body: nil)
    assert_not rev.valid?
    assert_includes rev.errors[:body], "can't be blank"
  end

  test "season enum exposes prefix predicates" do
    rev = create(:club_rules_revision, club: @club, edited_by_user: @user, season: :ice)
    assert rev.season_ice?
    assert_not rev.season_open_water?
  end

  test "latest_for returns the most recent revision for the (club, season)" do
    older = create(:club_rules_revision, club: @club, edited_by_user: @user,
                                         season: :open_water, body: "old",
                                         created_at: 2.days.ago)
    newer = create(:club_rules_revision, club: @club, edited_by_user: @user,
                                         season: :open_water, body: "new",
                                         created_at: 1.day.ago)

    assert_equal newer, ClubRulesRevision.latest_for(club: @club, season: :open_water)
    assert_not_equal older, ClubRulesRevision.latest_for(club: @club, season: :open_water)
  end

  test "latest_for is scoped per club" do
    other_club = create(:club)
    other_user = create(:user, club: other_club)
    create(:club_rules_revision, club: other_club, edited_by_user: other_user, season: :open_water)

    assert_nil ClubRulesRevision.latest_for(club: @club, season: :open_water)
  end

  test "latest_for is scoped per season" do
    create(:club_rules_revision, club: @club, edited_by_user: @user, season: :open_water)

    assert_nil ClubRulesRevision.latest_for(club: @club, season: :ice)
  end
end
