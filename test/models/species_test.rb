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

  test "in_log_order returns species in LOG_ORDER sequence, not insertion or alphabetical order" do
    # Created in reverse LOG_ORDER so neither insertion order nor alphabetical
    # order would coincidentally produce the expected result.
    Species::LOG_ORDER.reverse.each { |name| create(:species, name: name) }

    assert_equal Species::LOG_ORDER, Species.in_log_order.map(&:name)
  end

  test "in_log_order puts species not in LOG_ORDER at the end, alphabetically" do
    create(:species, name: "Sturgeon")
    create(:species, name: "Walleye")
    create(:species, name: "Crappie")

    # Walleye is listed (index 0); Crappie and Sturgeon are not, so they
    # fall to the end ordered alphabetically.
    assert_equal %w[Walleye Crappie Sturgeon], Species.in_log_order.map(&:name)
  end
end
