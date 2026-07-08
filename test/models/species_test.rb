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

  test "in_log_order matches LOG_ORDER case-insensitively" do
    # name uniqueness is case-insensitive, so a species could be stored with
    # casing that differs from LOG_ORDER's entries — it must still sort by rank.
    create(:species, name: "perch")
    create(:species, name: "WALLEYE")

    assert_equal %w[WALLEYE perch], Species.in_log_order.map(&:name)
  end

  test "walleye? matches ordinary Walleye but not Tagged Walleye" do
    assert     Species.new(name: "Walleye").walleye?
    assert     Species.new(name: "walleye").walleye?
    assert_not Species.new(name: "Tagged Walleye").walleye?
    assert_not Species.new(name: "Pike").walleye?
  end
end
