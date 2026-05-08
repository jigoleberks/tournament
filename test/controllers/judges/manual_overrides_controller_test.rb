require "test_helper"

class Judges::ManualOverridesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    @walleye = create(:species, club: @club)
    @pike = create(:species, club: @club)
    create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)
    create(:scoring_slot, tournament: @t, species: @pike, slot_count: 1)
    @judge = create(:user, club: @club)
    create(:tournament_judge, tournament: @t, user: @judge)
    angler = create(:user, club: @club)
    entry = create(:tournament_entry, tournament: @t)
    create(:tournament_entry_member, tournament_entry: entry, user: angler)
    @catch = create(:catch, user: angler, species: @walleye, length_inches: 20)
    Catches::PlaceInSlots.call(catch: @catch)
    sign_in_as(@judge)
  end

  test "POST changes length and notes the override" do
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { length_inches: "19.75", note: "tail" }
    assert_equal 19.75, @catch.reload.length_inches.to_f
  end

  test "POST with length and length_unit=inches stores inches as-is" do
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { length: "19.5", length_unit: "inches", note: "remeasured" }
    assert_equal 19.5, @catch.reload.length_inches.to_f
  end

  test "POST with length and length_unit=centimeters converts cm to inches" do
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { length: "50", length_unit: "centimeters", note: "remeasured" }
    # 50 cm / 2.54 = 19.685 in, stored to 2dp by the schema (~19.69)
    assert_in_delta 19.685, @catch.reload.length_inches.to_f, 0.01
  end

  test "GET new on a catch from another tournament is not found" do
    foreign_catch = build_foreign_catch
    get new_judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: foreign_catch.id)
    assert_response :not_found
  end

  test "POST override on a catch from another tournament is not found" do
    foreign_catch = build_foreign_catch
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: foreign_catch.id),
         params: { length_inches: "40", note: "drive-by" }
    assert_response :not_found
    assert_equal 21, foreign_catch.reload.length_inches.to_f
  end

  test "POST with species_id changes the catch's species" do
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { species_id: @pike.id, note: "misidentified" }

    @catch.reload
    assert_equal @pike.id, @catch.species_id
    assert_equal @pike.id, @catch.catch_placements.active.first.species_id
  end

  test "POST override with entry from another tournament is not found" do
    other_t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    other_entry = create(:tournament_entry, tournament: other_t)
    create(:scoring_slot, tournament: other_t, species: @walleye, slot_count: 1)

    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { slot_index: "0", entry_id: other_entry.id, note: "drive-by" }
    assert_response :not_found
    assert_equal 0, other_entry.catch_placements.count
  end

  private

  def build_foreign_catch
    other_t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    other_angler = create(:user, club: @club)
    other_entry = create(:tournament_entry, tournament: other_t)
    create(:tournament_entry_member, tournament_entry: other_entry, user: other_angler)
    create(:scoring_slot, tournament: other_t, species: @walleye, slot_count: 1)
    foreign_catch = create(:catch, user: other_angler, species: @walleye, length_inches: 21, status: :synced)
    Catches::PlaceInSlots.call(catch: foreign_catch)
    foreign_catch
  end

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
