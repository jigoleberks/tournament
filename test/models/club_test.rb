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
end
