require "test_helper"

class Tournaments::CatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @walleye = create(:species, club: @club)
    @member = create(:user, club: @club, name: "Member M", role: :member)
    @other  = create(:user, club: @club, name: "Other O", role: :member)

    @tournament = create(:tournament, club: @club,
                         starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                         blind_leaderboard: false)
    create(:scoring_slot, tournament: @tournament, species: @walleye, slot_count: 1)

    entry = create(:tournament_entry, tournament: @tournament, name: "Other Boat")
    create(:tournament_entry_member, tournament_entry: entry, user: @other)

    @catch = create(:catch, user: @other, species: @walleye, length_inches: 22.5,
                            captured_at_device: 30.minutes.ago)
    create(:catch_placement, catch: @catch, tournament: @tournament,
                              tournament_entry: entry, species: @walleye, slot_index: 0)
  end

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end

  test "signed-in member sees photo, species, length, angler, date for non-blind tournament with active placement" do
    sign_in_as(@member)

    get tournament_catch_path(@tournament, @catch)

    assert_response :ok
    body = @response.body
    assert_match %r{<img[^>]*src=["'][^"']*active_storage[^"']*}, body, "should include an Active Storage image"
    assert_match @walleye.name, body
    assert_match "22.5", body, "length in inches should be present"
    assert_match @other.name, body, "angler name should be present"
    refute_match "Notes (private)", body, "no notes field on the modal"
    refute_match "GPS:", body, "no GPS coordinates on the modal"
  end

  test "active blind tournament returns 404 even when member would otherwise have access" do
    blind = create(:tournament, club: @club,
                   starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                   blind_leaderboard: true)
    create(:scoring_slot, tournament: blind, species: @walleye, slot_count: 1)
    blind_entry = create(:tournament_entry, tournament: blind, name: "Other Blind")
    create(:tournament_entry_member, tournament_entry: blind_entry, user: @other)
    blind_catch = create(:catch, user: @other, species: @walleye, length_inches: 18.0,
                                  captured_at_device: 15.minutes.ago)
    create(:catch_placement, catch: blind_catch, tournament: blind,
                              tournament_entry: blind_entry, species: @walleye, slot_index: 0)

    sign_in_as(@member)

    get tournament_catch_path(blind, blind_catch)

    assert_response :not_found
  end

  test "ended blind tournament returns 200 — gate opens after ends_at" do
    ended_blind = create(:tournament, club: @club,
                         starts_at: 2.hours.ago, ends_at: 1.hour.ago,
                         blind_leaderboard: true)
    create(:scoring_slot, tournament: ended_blind, species: @walleye, slot_count: 1)
    e = create(:tournament_entry, tournament: ended_blind, name: "Ended Blind Entry")
    create(:tournament_entry_member, tournament_entry: e, user: @other)
    c = create(:catch, user: @other, species: @walleye, length_inches: 19.0,
                       captured_at_device: 90.minutes.ago)
    create(:catch_placement, catch: c, tournament: ended_blind,
                              tournament_entry: e, species: @walleye, slot_index: 0)

    sign_in_as(@member)

    get tournament_catch_path(ended_blind, c)

    assert_response :ok
    body = @response.body
    assert_match %r{<img[^>]*src=["'][^"']*active_storage[^"']*}, body, "should include the photo"
    assert_match @walleye.name, body
    assert_match "19.0", body
    assert_match @other.name, body
  end

  test "catch with no active placement in this tournament returns 404" do
    other_tournament = create(:tournament, club: @club,
                              starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                              blind_leaderboard: false)
    create(:scoring_slot, tournament: other_tournament, species: @walleye, slot_count: 1)

    sign_in_as(@member)

    get tournament_catch_path(other_tournament, @catch)

    assert_response :not_found
  end

  test "member of a different club returns 404" do
    other_club = create(:club)
    create(:species, club: other_club)
    outsider = create(:user, club: other_club, name: "Outsider X", role: :member)

    sign_in_as(outsider)

    get tournament_catch_path(@tournament, @catch)

    assert_response :not_found
  end

  test "not signed in redirects to sign-in" do
    get tournament_catch_path(@tournament, @catch)

    assert_redirected_to new_session_path
  end
end
