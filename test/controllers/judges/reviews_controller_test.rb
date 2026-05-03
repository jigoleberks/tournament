require "test_helper"

class Judges::ReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    @walleye = create(:species, club: @club)
    create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)
    @judge = create(:user, club: @club)
    create(:tournament_judge, tournament: @t, user: @judge)
    angler = create(:user, club: @club)
    entry = create(:tournament_entry, tournament: @t)
    create(:tournament_entry_member, tournament_entry: entry, user: angler)
    @catch = create(:catch, user: angler, species: @walleye, length_inches: 20, status: :needs_review)
    Catches::PlaceInSlots.call(catch: @catch)
    sign_in_as(@judge)
  end

  test "POST approve transitions needs_review -> synced" do
    post judges_tournament_catch_review_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { action_kind: "approve", note: "ok" }
    assert @catch.reload.synced?
  end

  test "POST disqualify deactivates placements" do
    post judges_tournament_catch_review_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { action_kind: "disqualify", note: "bad photo" }
    assert_equal 0, @catch.catch_placements.active.count
  end

  test "POST disqualify with blank note is rejected" do
    post judges_tournament_catch_review_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { action_kind: "disqualify", note: "" }
    assert @catch.reload.needs_review?, "blank-note DQ must not flip status"
    assert @catch.catch_placements.active.exists?, "blank-note DQ must not deactivate placements"
    assert_match(/reason note is required/i, flash[:alert])
  end

  test "POST approve on judge's own catch is rejected" do
    own_entry = create(:tournament_entry, tournament: @t)
    create(:tournament_entry_member, tournament_entry: own_entry, user: @judge)
    own_catch = create(:catch, user: @judge, species: @walleye, length_inches: 22, status: :needs_review)
    Catches::PlaceInSlots.call(catch: own_catch)

    post judges_tournament_catch_review_path(tournament_id: @t.id, catch_id: own_catch.id),
         params: { action_kind: "approve", note: "self" }
    assert own_catch.reload.needs_review?, "self-approval must not flip status"
    assert_match(/own catch/i, flash[:alert])
  end

  test "POST review on a catch from another tournament is not found" do
    other_t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    other_angler = create(:user, club: @club)
    other_entry = create(:tournament_entry, tournament: other_t)
    create(:tournament_entry_member, tournament_entry: other_entry, user: other_angler)
    create(:scoring_slot, tournament: other_t, species: @walleye, slot_count: 1)
    foreign_catch = create(:catch, user: other_angler, species: @walleye, length_inches: 21, status: :synced)
    Catches::PlaceInSlots.call(catch: foreign_catch)

    post judges_tournament_catch_review_path(tournament_id: @t.id, catch_id: foreign_catch.id),
         params: { action_kind: "disqualify", note: "drive-by" }
    assert_response :not_found
    assert foreign_catch.reload.synced?, "foreign catch must not have been disqualified"
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
