require "test_helper"

class CatchPlacementTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @walleye = create(:species, club: @club)
    @tournament = create(:tournament, club: @club)
    @entry = create(:tournament_entry, tournament: @tournament)
    @catch = create(:catch, user: @user, species: @walleye)
  end

  test "scoped to a (catch, tournament_entry, species, slot_index) tuple" do
    create(:catch_placement, catch: @catch, tournament: @tournament,
           tournament_entry: @entry, species: @walleye, slot_index: 0)
    duplicate = build(:catch_placement, catch: @catch, tournament: @tournament,
                      tournament_entry: @entry, species: @walleye, slot_index: 0)
    assert_not duplicate.valid?
  end

  test "active defaults to true" do
    placement = create(:catch_placement, catch: @catch, tournament: @tournament,
                       tournament_entry: @entry, species: @walleye, slot_index: 0)
    assert placement.active?
  end
end
