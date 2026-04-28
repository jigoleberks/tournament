require "test_helper"

class Judges::CatchesControllerTest < ActionDispatch::IntegrationTest
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
    @needs_review = create(:catch, user: angler, species: @walleye, length_inches: 20, status: :needs_review)
    @synced       = create(:catch, user: angler, species: @walleye, length_inches: 18, status: :synced)
    Catches::PlaceInSlots.call(catch: @synced)

    sign_in_as(@judge)
  end

  test "index lists all catches with needs_review pinned" do
    get judges_tournament_catches_path(tournament_id: @t.id)
    assert_response :success
    body = response.body
    needs_review_marker = "<td>#{@needs_review.id}</td>"
    synced_marker       = "<td>#{@synced.id}</td>"
    assert_includes body, needs_review_marker
    assert_includes body, synced_marker
    assert body.index(needs_review_marker) < body.index(synced_marker),
           "needs_review should come before synced in the listing"
  end

  test "non-judge sees forbidden" do
    other = create(:user, club: @club)
    sign_in_as(other)
    get judges_tournament_catches_path(tournament_id: @t.id)
    assert_response :forbidden
  end

  test "GET show on a catch from another tournament is not found" do
    foreign_catch = create_foreign_synced_catch
    get judges_tournament_catch_path(tournament_id: @t.id, id: foreign_catch.id)
    assert_response :not_found
  end

  test "index does not list catches from other tournaments" do
    foreign_catch = create_foreign_synced_catch
    get judges_tournament_catches_path(tournament_id: @t.id)
    assert_response :success
    assert_not_includes response.body, "<td>#{foreign_catch.id}</td>"
  end

  private

  def create_foreign_synced_catch
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
