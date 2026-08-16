require "test_helper"

class BoatTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @captain = create(:user, club: @club, name: "Kurtis Sanguin")
  end

  test "strips surrounding whitespace from the name" do
    boat = Boat.create!(club: @club, name: "  Majestic Red  ", captain: @captain)
    assert_equal "Majestic Red", boat.name
  end

  test "rejects a duplicate name in the same club regardless of case" do
    Boat.create!(club: @club, name: "Majestic Red", captain: @captain)
    dupe = Boat.new(club: @club, name: "majestic red", captain: @captain)
    assert_not dupe.valid?
    assert_includes dupe.errors[:name], "is already a boat in this club"
  end

  test "allows the same name in a different club" do
    other_club = create(:club)
    other_captain = create(:user, club: other_club)
    Boat.create!(club: @club, name: "Majestic Red", captain: @captain)
    assert Boat.new(club: other_club, name: "Majestic Red", captain: other_captain).valid?
  end

  test "requires the captain to be an active member of the boat's club" do
    outsider = create(:user, club: create(:club))
    boat = Boat.new(club: @club, name: "Stratos", captain: outsider)
    assert_not boat.valid?
    assert_includes boat.errors[:captain], "must be an active member of this club"
  end

  test "label reads name then captain" do
    boat = Boat.create!(club: @club, name: "Majestic Red", captain: @captain)
    assert_equal "Majestic Red — Kurtis Sanguin", boat.label
  end

  test "alphabetical sorts by name case-insensitively" do
    create(:boat, club: @club, name: "the pearl", captain: @captain)
    create(:boat, club: @club, name: "Big Tiller", captain: create(:user, club: @club))
    assert_equal ["Big Tiller", "the pearl"], @club.boats.alphabetical.pluck(:name)
  end
end
