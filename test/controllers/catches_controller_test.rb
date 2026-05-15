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

  test "show: hides possible-duplicate badge from member viewing own catch" do
    own = create(:catch, user: @user, species: @walleye, length_inches: 18.5,
                         flags: ["missing_gps", "possible_duplicate"], status: :needs_review)
    get catch_path(own.id)
    assert_response :success
    assert_match "no GPS", response.body
    refute_match "possible duplicate", response.body
  end

  test "index: hides possible-duplicate badge from member on own catches list" do
    create(:catch, user: @user, species: @walleye, length_inches: 18.5,
                   flags: ["possible_duplicate"], status: :needs_review,
                   captured_at_device: Time.current)
    get catches_path
    assert_response :success
    refute_match "possible duplicate", response.body
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

  test "show: organizer sees possible-duplicate badge" do
    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18.5,
                                  flags: ["possible_duplicate"], status: :needs_review)
    organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(organizer)

    get catch_path(catch_record.id)
    assert_response :success
    assert_match "possible duplicate", response.body
  end

  test "show: judge of the relevant tournament sees possible-duplicate badge" do
    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18.5,
                                  flags: ["possible_duplicate"], status: :needs_review)
    Catches::PlaceInSlots.call(catch: catch_record)
    judge = create(:user, club: @club)
    create(:tournament_judge, tournament: @tournament, user: judge)
    sign_in_as(judge)

    get catch_path(catch_record.id)
    assert_response :success
    assert_match "possible duplicate", response.body
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
    assert_match Time.current.strftime("%B %Y"), response.body
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

    d = 1.day.ago.to_date.iso8601
    get map_catches_path(start: d, end: d)
    assert_response :success
    assert_select "a[href=?]", catch_path(yesterday_catch.id)
    assert_select "a[href=?]", catch_path(today_catch.id), count: 0
  end

  test "map: unparseable date param falls back to today instead of 500ing" do
    get map_catches_path(start: "banana", end: "banana")
    assert_response :success
    assert_match Time.current.strftime("%B %Y"), response.body
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

  test "show: organizer sees Approve button when catch is synced" do
    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18.5, status: :synced)
    Catches::PlaceInSlots.call(catch: catch_record)
    organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(organizer)

    get catch_path(catch_record.id, t: @tournament.id)
    assert_response :success
    assert_select "form[action=?]",
      judges_tournament_catch_review_path(tournament_id: @tournament.id, catch_id: catch_record.id) do
      assert_select "input[name=?][value=?]", "action_kind", "approve"
      assert_select "button", text: "Approve"
    end
  end

  test "show: organizer sees Approve button when catch is disputed" do
    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18.5, status: :disputed)
    Catches::PlaceInSlots.call(catch: catch_record)
    organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(organizer)

    get catch_path(catch_record.id, t: @tournament.id)
    assert_response :success
    assert_select "input[name=?][value=?]", "action_kind", "approve"
  end

  test "show: shows 'Approved by X' instead of Approve button when catch already has an approver" do
    approver = create(:user, club: @club, role: :organizer, name: "Pat Approver")
    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18.5, status: :synced)
    Catches::PlaceInSlots.call(catch: catch_record)
    create(:judge_action, judge_user: approver, catch: catch_record, action: :approve)

    viewer = create(:user, club: @club, role: :organizer)
    sign_in_as(viewer)

    get catch_path(catch_record.id, t: @tournament.id)
    assert_response :success
    assert_select "input[name=?][value=?]", "action_kind", "approve", count: 0
    assert_match "Approved by Pat Approver", response.body
  end

  test "show: owner who is an organizer sees 'can't approve own catch' instead of Approve button" do
    @user.club_memberships.find_by(club: @club).update!(role: :organizer)
    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18.5, status: :synced)
    Catches::PlaceInSlots.call(catch: catch_record)

    get catch_path(catch_record.id, t: @tournament.id)
    assert_response :success
    assert_select "input[name=?][value=?]", "action_kind", "approve", count: 0
    assert_match "You can't approve your own catch", response.body
  end

  test "show: Approve button is hidden when catch is disqualified" do
    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18.5, status: :disqualified)
    # Real-world flow: the catch was placed first, then a judge DQ'd it — the
    # placement row stays with active: false. PlaceInSlots correctly refuses to
    # place a DQ'd catch, so mirror that final state directly here.
    create(:catch_placement, catch: catch_record, tournament: @tournament,
           tournament_entry: @entry, species: @walleye, active: false)
    judge = create(:user, club: @club)
    create(:tournament_judge, tournament: @tournament, user: judge)
    sign_in_as(judge)

    get catch_path(catch_record.id, t: @tournament.id)
    assert_response :success
    assert_select "input[name=?][value=?]", "action_kind", "approve", count: 0
  end

  test "GET /catches?start=2026-05-05&end=2026-05-12 returns only catches in range" do
    in_range  = create_catch(captured_at: Time.zone.parse("2026-05-08 10:00"))
    too_early = create_catch(captured_at: Time.zone.parse("2026-05-04 10:00"))
    too_late  = create_catch(captured_at: Time.zone.parse("2026-05-13 10:00"))

    get catches_path, params: { start: "2026-05-05", end: "2026-05-12" }
    assigned = assigns(:catches).to_a

    assert_includes  assigned, in_range
    refute_includes  assigned, too_early
    refute_includes  assigned, too_late
  end

  test "GET /catches?start=2026-05-12&end=2026-05-05 swaps and returns inclusive range" do
    in_range = create_catch(captured_at: Time.zone.parse("2026-05-08 10:00"))
    get catches_path, params: { start: "2026-05-12", end: "2026-05-05" }
    assert_includes assigns(:catches).to_a, in_range
    assert_equal Date.new(2026, 5, 5),  assigns(:selected_start)
    assert_equal Date.new(2026, 5, 12), assigns(:selected_end)
  end

  test "GET /catches?start=2026-05-05 with no end is treated as single day" do
    in_range = create_catch(captured_at: Time.zone.parse("2026-05-05 10:00"))
    out_of   = create_catch(captured_at: Time.zone.parse("2026-05-06 10:00"))
    get catches_path, params: { start: "2026-05-05" }
    assert_includes assigns(:catches).to_a, in_range
    refute_includes assigns(:catches).to_a, out_of
  end

  test "GET /catches?start=&end= treats explicit empty as no date filter" do
    a = create_catch(captured_at: 3.days.ago)
    b = create_catch(captured_at: 30.days.ago)
    get catches_path, params: { start: "", end: "" }
    assigned = assigns(:catches).to_a
    assert_includes assigned, a
    assert_includes assigned, b
    assert_nil assigns(:selected_start)
    assert_nil assigns(:selected_end)
  end

  test "GET /catches with no params defaults to today (single day)" do
    today_catch = create_catch(captured_at: Time.zone.now.change(hour: 12))
    yesterday_catch = create_catch(captured_at: 1.day.ago.change(hour: 12))
    get catches_path
    assigned = assigns(:catches).to_a
    assert_includes assigned, today_catch
    refute_includes assigned, yesterday_catch
    assert_equal Date.current, assigns(:selected_start)
    assert_equal Date.current, assigns(:selected_end)
  end

  test "GET /catches with no params and no catches today falls back to most recent day with catches" do
    older = create_catch(captured_at: 5.days.ago.change(hour: 12))
    get catches_path
    assert_equal older.captured_at_device.to_date, assigns(:selected_start)
    assert_equal older.captured_at_device.to_date, assigns(:selected_end)
    assert_includes assigns(:catches).to_a, older
  end

  test "GET /catches?species=ID filters to that species" do
    pike = create(:species, club: @club, name: "Pike")
    walleye_catch = create_catch(captured_at: 1.day.ago, species: @walleye)
    pike_catch    = create_catch(captured_at: 1.day.ago, species: pike)
    get catches_path, params: { species: pike.id, start: "", end: "" }
    assigned = assigns(:catches).to_a
    assert_includes assigned, pike_catch
    refute_includes assigned, walleye_catch
  end

  test "GET /catches?sort=longest orders by length descending" do
    short = create_catch(captured_at: 1.hour.ago, length: 14.0)
    long  = create_catch(captured_at: 2.hours.ago, length: 32.0)
    mid   = create_catch(captured_at: 3.hours.ago, length: 22.0)
    get catches_path, params: { sort: "longest", start: "", end: "" }
    assigned = assigns(:catches).to_a
    assert_equal [long, mid, short], assigned.first(3)
  end

  test "GET /catches?sort=shortest orders by length ascending" do
    a = create_catch(captured_at: 1.hour.ago, length: 14.0)
    b = create_catch(captured_at: 2.hours.ago, length: 32.0)
    c = create_catch(captured_at: 3.hours.ago, length: 22.0)
    get catches_path, params: { sort: "shortest", start: "", end: "" }
    assert_equal [a, c, b], assigns(:catches).to_a.first(3)
  end

  test "GET /catches?sort=newest is default ordering by captured_at_device desc" do
    older  = create_catch(captured_at: 3.days.ago)
    newer  = create_catch(captured_at: 1.day.ago)
    middle = create_catch(captured_at: 2.days.ago)
    get catches_path, params: { sort: "newest", start: "", end: "" }
    assert_equal [newer, middle, older], assigns(:catches).to_a.first(3)
  end

  test "GET /catches with species + sort + range — all three apply" do
    pike = create(:species, club: @club, name: "Pike")
    target = create_catch(captured_at: Time.zone.parse("2026-05-08 10:00"), length: 30.0, species: pike)
    other_species = create_catch(captured_at: Time.zone.parse("2026-05-08 10:00"), length: 35.0, species: @walleye)
    out_of_range  = create_catch(captured_at: Time.zone.parse("2026-04-08 10:00"), length: 50.0, species: pike)
    get catches_path, params: { start: "2026-05-05", end: "2026-05-12",
                                species: pike.id, sort: "longest" }
    assigned = assigns(:catches).to_a
    assert_includes assigned, target
    refute_includes assigned, other_species
    refute_includes assigned, out_of_range
  end

  test "GET /catches assigns @month_start to the selected month's first day" do
    create_catch(captured_at: Time.zone.parse("2026-05-08 10:00"))
    get catches_path, params: { start: "2026-05-08", end: "2026-05-08" }
    assert_equal Date.new(2026, 5, 1), assigns(:month_start)
  end

  test "GET /catches assigns @counts_by_date for the displayed month" do
    create_catch(captured_at: Time.zone.parse("2026-05-08 10:00"))
    create_catch(captured_at: Time.zone.parse("2026-05-08 14:00"))
    create_catch(captured_at: Time.zone.parse("2026-05-12 10:00"))
    create_catch(captured_at: Time.zone.parse("2026-04-30 10:00"))
    create_catch(captured_at: Time.zone.parse("2026-06-01 10:00"))

    get catches_path, params: { start: "2026-05-08", end: "2026-05-08" }
    counts = assigns(:counts_by_date)
    assert_equal 2, counts[Date.new(2026, 5, 8)]
    assert_equal 1, counts[Date.new(2026, 5, 12)]
    assert_nil counts[Date.new(2026, 4, 30)]
    assert_nil counts[Date.new(2026, 6, 1)]
  end

  test "GET /catches counts_by_date buckets by Time.zone-local date, not UTC" do
    Time.use_zone("America/Regina") do
      # 11pm Regina May 8 = 5am UTC May 9. Buggy DATE(captured_at_device)
      # would bucket onto May 9; fixed code keys by local date (May 8).
      late_evening = Time.zone.local(2026, 5, 8, 23, 0)
      create_catch(captured_at: late_evening)
      get catches_path, params: { start: "2026-05-08", end: "2026-05-08", month: "2026-05-01" }
      counts = assigns(:counts_by_date)
      assert_equal 1, counts[Date.new(2026, 5, 8)]
      assert_nil counts[Date.new(2026, 5, 9)]
    end
  end

  test "GET /catches?month=2026-05-01 controls the displayed month independently of selection" do
    create_catch(captured_at: Time.zone.parse("2026-05-15 10:00"))
    get catches_path, params: { start: "", end: "", month: "2026-05-01" }
    assert_equal Date.new(2026, 5, 1), assigns(:month_start)
    assert_equal 1, assigns(:counts_by_date)[Date.new(2026, 5, 15)]
  end

  test "GET /catches assigns @available_species ordered by name" do
    pike  = create(:species, club: @club, name: "Pike")
    perch = create(:species, club: @club, name: "Perch")
    get catches_path
    names = assigns(:available_species).map(&:name)
    assert_equal %w[Perch Pike Walleye], names
  end

  test "GET /catches renders the catch calendar with a count badge for days that have catches" do
    create_catch(captured_at: Time.zone.parse("2026-05-08 10:00"))
    get catches_path, params: { start: "2026-05-08", end: "2026-05-08", month: "2026-05-01" }
    assert_response :ok
    assert_select "[data-test='catch-calendar']"
    assert_select "[data-test='calendar-day-2026-05-08']"
    assert_select "[data-test='calendar-day-2026-05-08'] [data-test='count-badge']", text: /1/
    assert_select "[data-test='calendar-day-2026-05-09'] [data-test='count-badge']", count: 0
  end

  test "GET /catches calendar marks the selected day with selected styling" do
    create_catch(captured_at: Time.zone.parse("2026-05-08 10:00"))
    get catches_path, params: { start: "2026-05-08", end: "2026-05-08", month: "2026-05-01" }
    assert_select "[data-test='calendar-day-2026-05-08'][data-selected='true']"
  end

  test "GET /catches renders Show all dates link that clears start/end but keeps species/sort" do
    get catches_path, params: { start: "2026-05-08", species: "0", sort: "longest" }
    assert_select "a[data-test='show-all-dates']" do |els|
      href = els.first["href"]
      assert_includes href, "sort=longest"
      refute_includes href, "start=2026-05-08"
    end
  end

  test "GET /catches renders species filter dropdown with All option and one per available species" do
    pike = create(:species, club: @club, name: "Pike")
    get catches_path
    assert_select "select[name='species']" do
      assert_select "option", text: "All species"
      assert_select "option[value='#{pike.id}']", text: "Pike"
      assert_select "option[value='#{@walleye.id}']", text: "Walleye"
    end
  end

  test "GET /catches?species=ID marks that option as selected" do
    pike = create(:species, club: @club, name: "Pike")
    get catches_path, params: { species: pike.id, start: "", end: "" }
    assert_select "select[name='species'] option[selected][value='#{pike.id}']"
  end

  test "GET /catches renders sort dropdown with the four labels and current selection" do
    get catches_path, params: { sort: "longest", start: "", end: "" }
    assert_select "select[name='sort'] option[selected][value='longest']"
    %w[newest longest shortest].each do |key|
      assert_select "select[name='sort'] option[value='#{key}']"
    end
  end

  test "GET /catches/map?start=2026-05-05&end=2026-05-12 returns catches in range with map points" do
    in_range = create_catch(captured_at: Time.zone.parse("2026-05-08 10:00"), length: 18.0)
    in_range.update!(latitude: 49.41, longitude: -103.62)
    out_of   = create_catch(captured_at: Time.zone.parse("2026-04-08 10:00"))

    get map_catches_path, params: { start: "2026-05-05", end: "2026-05-12" }
    assigned = assigns(:catches).to_a
    assert_includes assigned, in_range
    refute_includes assigned, out_of
    assert_kind_of Array, assigns(:map_points)
    assert_equal 1, assigns(:map_points).length
  end

  test "GET /catches/map with no params defaults to today (single day)" do
    today_catch = create_catch(captured_at: Time.zone.now.change(hour: 12))
    get map_catches_path
    assert_equal Date.current, assigns(:selected_start)
    assert_equal Date.current, assigns(:selected_end)
    assert_includes assigns(:catches).to_a, today_catch
  end

  test "GET /catches/map?species=ID filters" do
    pike = create(:species, club: @club, name: "Pike")
    walleye_catch = create_catch(captured_at: 1.hour.ago, species: @walleye)
    pike_catch    = create_catch(captured_at: 1.hour.ago, species: pike)
    get map_catches_path, params: { species: pike.id, start: "", end: "" }
    assigned = assigns(:catches).to_a
    assert_includes assigned, pike_catch
    refute_includes assigned, walleye_catch
  end

  test "GET /catches/map computes counts_by_date for the displayed month" do
    create_catch(captured_at: Time.zone.parse("2026-05-08 10:00"))
    create_catch(captured_at: Time.zone.parse("2026-05-12 10:00"))
    get map_catches_path, params: { start: "2026-05-08", end: "2026-05-08" }
    assert_equal 1, assigns(:counts_by_date)[Date.new(2026, 5, 8)]
    assert_equal 1, assigns(:counts_by_date)[Date.new(2026, 5, 12)]
  end

  # --- Teammate catch logging --------------------------------------------------
  # @tournament defaults to solo (one angler per entry); these tests need team mode.

  test "GET /catches/select_teammate lists same-entry teammates" do
    @tournament.update!(mode: :team)
    teammate = create(:user, club: @club, name: "Boatmate")
    create(:tournament_entry_member, tournament_entry: @entry, user: teammate)
    other = create(:user, club: @club, name: "Other Boat")
    other_entry = create(:tournament_entry, tournament: @tournament)
    create(:tournament_entry_member, tournament_entry: other_entry, user: other)

    get select_teammate_catches_path(tournament_id: @tournament.id)
    assert_response :success
    assert_match "Boatmate", response.body
    assert_no_match "Other Boat", response.body
  end

  test "GET /catches/select_teammate returns empty list when user has no entry" do
    other_tournament = create(:tournament, club: @club, name: "Other", mode: :team)
    get select_teammate_catches_path(tournament_id: other_tournament.id)
    assert_response :success
    assert_match "No teammates on your entry", response.body
  end

  test "GET /catches/select_teammate redirects for a solo tournament" do
    get select_teammate_catches_path(tournament_id: @tournament.id)
    assert_redirected_to tournament_path(@tournament)
  end

  test "tournament show hides 'Log for teammate' for solo tournaments" do
    get tournament_path(@tournament)
    assert_response :success
    assert_match "Log Catch", response.body
    assert_no_match "Log for teammate", response.body
  end

  test "tournament show shows 'Log for teammate' for team tournaments" do
    @tournament.update!(mode: :team)
    get tournament_path(@tournament)
    assert_response :success
    assert_match "Log for teammate", response.body
  end

  test "GET /catches/new with valid teammate_user_id assigns @teammate and shows banner" do
    @tournament.update!(mode: :team)
    teammate = create(:user, club: @club, name: "Boatmate")
    create(:tournament_entry_member, tournament_entry: @entry, user: teammate)
    get new_catch_path(teammate_user_id: teammate.id)
    assert_response :success
    assert_equal teammate, assigns(:teammate)
    assert_match "Logging for", response.body
    assert_match "Boatmate", response.body
  end

  test "GET /catches/new with foreign-club teammate redirects with alert" do
    other_club = create(:club)
    foreigner = create(:user, club: other_club)
    get new_catch_path(teammate_user_id: foreigner.id)
    assert_redirected_to new_catch_path
    assert_equal "Teammate not found.", flash[:alert]
  end

  test "POST /catches with valid teammate files catch under teammate and stamps logger" do
    @tournament.update!(mode: :team)
    teammate = create(:user, club: @club, name: "Boatmate")
    create(:tournament_entry_member, tournament_entry: @entry, user: teammate)
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    now = Time.current

    post catches_path, params: {
      teammate_user_id: teammate.id,
      catch: {
        species_id: @walleye.id,
        length_inches: 18.5,
        captured_at_device: now, captured_at_gps: now,
        latitude: 49.41, longitude: -103.62,
        client_uuid: "client-team-1", photo: photo
      }
    }
    assert_redirected_to root_path
    persisted = Catch.find_by(client_uuid: "client-team-1")
    assert_equal teammate.id, persisted.user_id
    assert_equal @user.id, persisted.logged_by_user_id
  end

  test "POST /catches with teammate from another entry rejects" do
    other_user = create(:user, club: @club)
    other_entry = create(:tournament_entry, tournament: @tournament)
    create(:tournament_entry_member, tournament_entry: other_entry, user: other_user)
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    now = Time.current

    assert_no_difference -> { Catch.count } do
      post catches_path, params: {
        teammate_user_id: other_user.id,
        catch: {
          species_id: @walleye.id, length_inches: 18.5,
          captured_at_device: now, captured_at_gps: now,
          latitude: 49.41, longitude: -103.62,
          client_uuid: "client-team-bad", photo: photo
        }
      }
    end
    assert_response :unprocessable_entity
    assert_match "on the same entry", response.body
  end

  test "POST /catches with teammate when no tournament is active rejects" do
    @tournament.update!(mode: :team)
    teammate = create(:user, club: @club)
    create(:tournament_entry_member, tournament_entry: @entry, user: teammate)
    @tournament.update!(starts_at: 3.days.ago, ends_at: 2.days.ago)
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")

    post catches_path, params: {
      teammate_user_id: teammate.id,
      catch: {
        species_id: @walleye.id, length_inches: 18.5,
        captured_at_device: Time.current, captured_at_gps: Time.current,
        latitude: 49.41, longitude: -103.62,
        client_uuid: "client-team-expired", photo: photo
      }
    }
    assert_response :unprocessable_entity
    assert_match "on the same entry", response.body
  end

  test "show: logger of a teammate's catch can view it" do
    @tournament.update!(mode: :team)
    teammate = create(:user, club: @club)
    create(:tournament_entry_member, tournament_entry: @entry, user: teammate)
    teammate_catch = create(:catch, user: teammate, species: @walleye,
                                    length_inches: 18.5, logged_by_user_id: @user.id)
    get catch_path(teammate_catch.id)
    assert_response :success
    assert_match "Logged by", response.body
  end

  test "show: conditions panel renders pressure in kPa, not hPa" do
    catch_record = create(:catch,
      user: @user, species: @walleye, length_inches: 18.5,
      barometric_pressure_hpa: 1013.25,
      moon_phase: "Full Moon"
    )

    get catch_path(catch_record.id)
    assert_response :success
    assert_match "101.3 kPa", response.body
    refute_match "hPa", response.body
  end

  test "show: conditions panel renders compass label after wind speed" do
    catch_record = create(:catch,
      user: @user, species: @walleye, length_inches: 18.5,
      wind_speed_kph: 12.0,
      wind_direction_deg: 315.0,           # NW
      moon_phase: "Full Moon"
    )

    get catch_path(catch_record.id)
    assert_response :success
    assert_match "12.0 km/h", response.body
    assert_match "NW", response.body
  end

  test "show: conditions panel omits compass label when wind_direction_deg is nil (legacy catch)" do
    catch_record = create(:catch,
      user: @user, species: @walleye, length_inches: 18.5,
      wind_speed_kph: 12.0,
      wind_direction_deg: nil,
      moon_phase: "Full Moon"
    )

    get catch_path(catch_record.id)
    assert_response :success
    assert_match "12.0 km/h", response.body
    # No compass label between speed and the next field — assert wind line ends cleanly.
    assert_no_match(/12\.0 km\/h \/ [\d\.]+ mph (?:N|NE|E|SE|S|SW|W|NW)/, response.body)
  end

  test "POST /catches sets lake when GPS falls inside a known polygon" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    post catches_path, params: {
      catch: { species_id: @walleye.id, length_inches: 18.5,
               captured_at_device: Time.current,
               latitude: 53.55, longitude: -103.65,
               client_uuid: "client-tobin", photo: photo }
    }
    assert_equal "tobin", Catch.find_by(client_uuid: "client-tobin").lake
  end

  test "POST /catches leaves lake nil when no GPS" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    post catches_path, params: {
      catch: { species_id: @walleye.id, length_inches: 18.5,
               captured_at_device: Time.current,
               client_uuid: "client-no-gps", photo: photo }
    }
    assert_nil Catch.find_by(client_uuid: "client-no-gps").lake
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end

  def create_catch(captured_at:, length: 18.0, species: @walleye, photo_attached: true)
    rec = build(:catch, user: @user, species: species, length_inches: length,
                        captured_at_device: captured_at)
    if photo_attached
      rec.photo.attach(io: file_fixture("sample_walleye.jpg").open,
                       filename: "sample_walleye.jpg", content_type: "image/jpeg")
    end
    rec.save!
    rec
  end
end
