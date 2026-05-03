require "test_helper"

class CatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @walleye = create(:species, club: @club, name: "Walleye")
    @tournament = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: @tournament, species: @walleye, slot_count: 2)
    @entry = create(:tournament_entry, tournament: @tournament)
    create(:tournament_entry_member, tournament_entry: @entry, user: @user)
    sign_in_as(@user)
  end

  test "POST /catches creates a catch and triggers placement" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")

    assert_difference -> { Catch.count } => 1, -> { CatchPlacement.count } => 1 do
      post catches_path, params: {
        catch: {
          species_id: @walleye.id,
          length_inches: 18.5,
          captured_at_device: Time.current,
          client_uuid: "client-1",
          photo: photo
        }
      }
    end

    placement = CatchPlacement.last
    assert_equal @entry, placement.tournament_entry
    assert_equal 0, placement.slot_index
  end

  test "POST /catches persists flags and sets needs_review when GPS missing" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    post catches_path, params: {
      catch: { species_id: @walleye.id, length_inches: 18.5,
               captured_at_device: Time.current,
               client_uuid: "client-flags", photo: photo }
    }
    persisted = Catch.find_by(client_uuid: "client-flags")
    assert_includes persisted.flags, "missing_gps"
    assert_equal "needs_review", persisted.status
  end

  test "POST /catches with in-bounds GPS has empty flags and synced status" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    now = Time.current
    post catches_path, params: {
      catch: { species_id: @walleye.id, length_inches: 18.5,
               captured_at_device: now, captured_at_gps: now,
               latitude: 49.41, longitude: -103.62,
               client_uuid: "client-clean", photo: photo }
    }
    persisted = Catch.find_by(client_uuid: "client-clean")
    assert_empty persisted.flags
    assert_equal "synced", persisted.status
  end

  test "show: renders flag badges with humanized labels for a flagged catch" do
    own = create(:catch, user: @user, species: @walleye, length_inches: 18.5,
                         flags: ["missing_gps", "out_of_bounds"], status: :needs_review)
    get catch_path(own.id)
    assert_response :success
    assert_match "no GPS", response.body
    assert_match "outside local", response.body
  end

  test "missing photo is rejected" do
    assert_no_difference "Catch.count" do
      post catches_path, params: {
        catch: { species_id: @walleye.id, length_inches: 14, captured_at_device: Time.current, client_uuid: "u" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "index lists only signed-in member's own catches" do
    own = create(:catch, user: @user, species: @walleye, length_inches: 18.5)
    other_user = create(:user, club: @club)
    other = create(:catch, user: other_user, species: @walleye, length_inches: 22)

    get catches_path
    assert_response :success
    assert_select "a[href=?]", catch_path(own.id)
    assert_select "a[href=?]", catch_path(other.id), count: 0
  end

  test "show: member can view their own catch detail" do
    own = create(:catch, user: @user, species: @walleye, length_inches: 18.5)
    get catch_path(own.id)
    assert_response :success
  end

  test "show: renders Save photo button with download wiring when photo attached" do
    own = create(:catch, user: @user, species: @walleye, length_inches: 18.5,
                         captured_at_device: Time.zone.local(2026, 4, 30, 14, 35))
    get catch_path(own.id)
    assert_response :success

    assert_select "[data-controller~=?]", "photo-save" do |containers|
      container = containers.first
      assert_match %r{rails/active_storage|/blobs/}, container["data-photo-save-url-value"],
                   "expected an Active Storage URL"
      assert_equal "Walleye - 18.5 in - 2026-04-30 1435.jpg",
                   container["data-photo-save-filename-value"]
    end
    assert_select "button[data-action=?]", "photo-save#save", text: "Save photo"
  end

  test "show: member cannot view another member's catch detail" do
    other_user = create(:user, club: @club)
    foreign = create(:catch, user: other_user, species: @walleye, length_inches: 22)
    get catch_path(foreign.id)
    assert_response :forbidden
  end

  test "show: organizer in friendly tournament sees DQ + edit-length actions" do
    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18.5)
    Catches::PlaceInSlots.call(catch: catch_record)
    organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(organizer)

    get catch_path(catch_record.id, t: @tournament.id)
    assert_response :success
    assert_select "form[action=?]",
      judges_tournament_catch_review_path(tournament_id: @tournament.id, catch_id: catch_record.id)
    assert_select "form[action=?]",
      judges_tournament_catch_manual_override_path(tournament_id: @tournament.id, catch_id: catch_record.id)
  end

  test "map: defaults to today, includes signed-in user's geolocated catches only" do
    own_with_gps = create(:catch, user: @user, species: @walleye, length_inches: 18.5,
                          captured_at_device: Time.current, latitude: 49.1, longitude: -97.2)
    own_without_gps = create(:catch, user: @user, species: @walleye, length_inches: 12,
                             captured_at_device: Time.current, latitude: nil, longitude: nil)
    other_user = create(:user, club: @club)
    other_user_catch = create(:catch, user: other_user, species: @walleye, length_inches: 22,
                              captured_at_device: Time.current, latitude: 49.1, longitude: -97.2)

    get map_catches_path
    assert_response :success
    assert_match Time.current.strftime("%A, %b %d"), response.body
    assert_select "a[href=?]", catch_path(own_with_gps.id)
    assert_select "a[href=?]", catch_path(own_without_gps.id)
    assert_select "a[href=?]", catch_path(other_user_catch.id), count: 0

    points = JSON.parse(css_select("[data-map-points-value]").first["data-map-points-value"])
    assert_equal 1, points.length
    assert_in_delta 49.1, points.first["lat"]
  end

  test "map: filters catches to the requested date" do
    yesterday_catch = create(:catch, user: @user, species: @walleye, length_inches: 18.5,
                             captured_at_device: 1.day.ago, latitude: 49.1, longitude: -97.2)
    today_catch = create(:catch, user: @user, species: @walleye, length_inches: 19,
                         captured_at_device: Time.current, latitude: 49.1, longitude: -97.2)

    get map_catches_path(date: 1.day.ago.to_date.iso8601)
    assert_response :success
    assert_select "a[href=?]", catch_path(yesterday_catch.id)
    assert_select "a[href=?]", catch_path(today_catch.id), count: 0
  end

  test "map: unparseable date param falls back to today instead of 500ing" do
    get map_catches_path(date: "banana")
    assert_response :success
    assert_match Time.current.strftime("%A, %b %d"), response.body
  end

  test "show: organizer in judged tournament does not see actions when not a judge" do
    @tournament.update!(judged: true)
    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18.5)
    Catches::PlaceInSlots.call(catch: catch_record)
    organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(organizer)

    get catch_path(catch_record.id, t: @tournament.id)
    assert_response :success
    assert_select "form[action=?]",
      judges_tournament_catch_review_path(tournament_id: @tournament.id, catch_id: catch_record.id),
      count: 0
  end

  test "update: owner can save a note" do
    own = create(:catch, user: @user, species: @walleye, length_inches: 18.5)
    patch catch_path(own.id), params: { catch: { note: "released near bridge" } }
    assert_redirected_to catch_path(own.id)
    assert_equal "released near bridge", own.reload.note
  end

  test "update: non-owner gets 404" do
    other_user = create(:user, club: @club)
    foreign = create(:catch, user: other_user, species: @walleye, length_inches: 18.5)
    patch catch_path(foreign.id), params: { catch: { note: "sneaky" } }
    assert_response :not_found
    assert_nil foreign.reload.note
  end

  test "update: strong-params discards non-note fields" do
    own = create(:catch, user: @user, species: @walleye, length_inches: 18.5)
    patch catch_path(own.id), params: { catch: { note: "ok", length_inches: 99 } }
    assert_redirected_to catch_path(own.id)
    own.reload
    assert_equal "ok", own.note
    assert_equal 18.5, own.length_inches.to_f
  end

  test "update: overly long note is rejected, re-renders show, and preserves typed text" do
    own = create(:catch, user: @user, species: @walleye, length_inches: 18.5)
    long_note = "a" * 501
    patch catch_path(own.id), params: { catch: { note: long_note } }
    assert_response :unprocessable_entity
    assert_nil own.reload.note
    assert_match "too long", response.body
    assert_match long_note, response.body
  end

  test "show: owner sees their note text and the edit form" do
    own = create(:catch, user: @user, species: @walleye, length_inches: 18.5,
                         note: "OWNER-NOTE-VISIBLE")
    get catch_path(own.id)
    assert_response :success
    assert_match "OWNER-NOTE-VISIBLE", response.body
    assert_select "form[action=?][method=?]", catch_path(own.id), "post" do
      assert_select "input[name=?][value=?]", "_method", "patch"
      assert_select "textarea[name=?]", "catch[note]"
    end
  end

  test "show: organizer cannot see another member's note" do
    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18.5,
                                  note: "OWNER-NOTE-HIDDEN")
    organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(organizer)
    get catch_path(catch_record.id)
    assert_response :success
    assert_no_match "OWNER-NOTE-HIDDEN", response.body
    assert_select "textarea[name=?]", "catch[note]", count: 0
  end

  test "show: judge sees Approve button when catch is needs_review" do
    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18.5, status: :needs_review)
    Catches::PlaceInSlots.call(catch: catch_record)
    judge = create(:user, club: @club)
    create(:tournament_judge, tournament: @tournament, user: judge)
    sign_in_as(judge)

    get catch_path(catch_record.id, t: @tournament.id)
    assert_response :success
    assert_select "form[action=?]",
      judges_tournament_catch_review_path(tournament_id: @tournament.id, catch_id: catch_record.id) do
      assert_select "input[name=?][value=?]", "action_kind", "approve"
      assert_select "button", text: "Approve"
    end
  end

  test "show: Approve button is hidden when catch is synced" do
    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18.5, status: :synced)
    Catches::PlaceInSlots.call(catch: catch_record)
    judge = create(:user, club: @club)
    create(:tournament_judge, tournament: @tournament, user: judge)
    sign_in_as(judge)

    get catch_path(catch_record.id, t: @tournament.id)
    assert_response :success
    assert_select "input[name=?][value=?]", "action_kind", "approve", count: 0
  end

  test "show: Approve button is hidden when catch is disqualified" do
    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18.5, status: :disqualified)
    Catches::PlaceInSlots.call(catch: catch_record)
    judge = create(:user, club: @club)
    create(:tournament_judge, tournament: @tournament, user: judge)
    sign_in_as(judge)

    get catch_path(catch_record.id, t: @tournament.id)
    assert_response :success
    assert_select "input[name=?][value=?]", "action_kind", "approve", count: 0
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
