require "test_helper"

class SpeciesTest < ActiveSupport::TestCase
  setup { @club = create(:club) }

  test "name is required and unique within a club" do
    create(:species, club: @club, name: "Walleye")
    duplicate = build(:species, club: @club, name: "Walleye")
    assert_not duplicate.valid?
  end

  test "two clubs can each have their own Walleye" do
    other = create(:club)
    create(:species, club: @club, name: "Walleye")
    assert build(:species, club: other, name: "Walleye").valid?
  end
end
