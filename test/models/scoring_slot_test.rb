require "test_helper"

class ScoringSlotTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @tournament = create(:tournament, club: @club)
    @walleye = create(:species, club: @club, name: "Walleye")
  end

  test "requires species, slot_count > 0, and a tournament" do
    assert_not ScoringSlot.new(tournament: @tournament).valid?
    bad = ScoringSlot.new(tournament: @tournament, species: @walleye, slot_count: 0)
    assert_not bad.valid?
  end

  test "uniqueness of species per tournament" do
    create(:scoring_slot, tournament: @tournament, species: @walleye, slot_count: 2)
    duplicate = build(:scoring_slot, tournament: @tournament, species: @walleye, slot_count: 1)
    assert_not duplicate.valid?
  end
end
