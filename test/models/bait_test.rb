require "test_helper"

class BaitTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
  end

  test "valid with all four attributes" do
    bait = build(:bait, user: @user)
    assert bait.valid?
  end

  test "valid when only bait_type is set" do
    bait = Bait.new(user: @user, bait_type: "nightcrawler")
    assert bait.valid?
  end

  test "valid when only color is set" do
    bait = Bait.new(user: @user, color: "chartreuse")
    assert bait.valid?
  end

  test "invalid when all four fields are blank" do
    bait = Bait.new(user: @user)
    assert_not bait.valid?
    assert_includes bait.errors[:base].join, "at least one"
  end

  test "invalid when all four fields are whitespace" do
    bait = Bait.new(user: @user, color: " ", weight: " ", lure_type: " ", bait_type: " ")
    assert_not bait.valid?
  end

  test "requires a user" do
    bait = Bait.new(bait_type: "minnow")
    assert_not bait.valid?
    assert_includes bait.errors[:user].join, "must exist"
  end

  test "rejects an attribute longer than the max" do
    bait = build(:bait, user: @user, color: "x" * (Bait::ATTR_MAX_LEN + 1))
    assert_not bait.valid?
  end

  test "display_name composes weight + color + lure_type + bait_type" do
    bait = Bait.new(user: @user, weight: "3/8 oz", color: "orange",
                    lure_type: "fireball", bait_type: "minnow")
    assert_equal "3/8 oz orange fireball + minnow", bait.display_name
  end

  test "display_name handles a lure-only bait" do
    bait = Bait.new(user: @user, weight: "1/4 oz", color: "white", lure_type: "jighead")
    assert_equal "1/4 oz white jighead", bait.display_name
  end

  test "display_name handles a bait-only entry" do
    bait = Bait.new(user: @user, bait_type: "nightcrawler")
    assert_equal "nightcrawler", bait.display_name
  end

  test "display_name strips whitespace and skips blank components" do
    bait = Bait.new(user: @user, weight: "  ", color: "green", lure_type: nil, bait_type: "")
    assert_equal "green", bait.display_name
  end

  test "archive! sets archived_at and archived? reflects it" do
    bait = create(:bait, user: @user)
    assert_not bait.archived?
    bait.archive!
    assert bait.archived?
    assert bait.archived_at.present?
  end

  test "unarchive! clears archived_at" do
    bait = create(:bait, user: @user, archived_at: Time.current)
    assert bait.archived?
    bait.unarchive!
    assert_not bait.archived?
  end

  test "active scope excludes archived baits" do
    active = create(:bait, user: @user)
    archived = create(:bait, user: @user, archived_at: Time.current)
    assert_includes Bait.active, active
    assert_not_includes Bait.active, archived
  end

  test "archived scope returns only archived baits" do
    active = create(:bait, user: @user)
    archived = create(:bait, user: @user, archived_at: Time.current)
    assert_includes Bait.archived, archived
    assert_not_includes Bait.archived, active
  end

  test "cannot be destroyed when catches reference it" do
    bait = create(:bait, user: @user)
    species = create(:species)
    create(:catch, user: @user, species: species, bait: bait)
    assert_not bait.destroy
    assert_includes bait.errors[:base].join, "Cannot delete"
  end
end
