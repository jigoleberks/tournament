require "test_helper"

class SpeciesTest < ActiveSupport::TestCase
  test "name is required and globally unique" do
    create(:species, name: "Walleye")
    duplicate = build(:species, name: "Walleye")
    assert_not duplicate.valid?
  end

  test "name uniqueness is case-insensitive" do
    create(:species, name: "Walleye")
    duplicate = build(:species, name: "walleye")
    assert_not duplicate.valid?
  end
end
