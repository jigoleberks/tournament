require "test_helper"

class Api::CatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @walleye = create(:species, club: @club)
    @tournament = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: @tournament, species: @walleye, slot_count: 2)
    entry = create(:tournament_entry, tournament: @tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)
    sign_in_as(@user)
  end

  test "POST /api/catches creates and places a catch" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    assert_difference -> { Catch.count } => 1, -> { CatchPlacement.count } => 1 do
      post "/api/catches", params: {
        catch: {
          species_id: @walleye.id,
          length_inches: 19.5,
          captured_at_device: Time.current.iso8601,
          captured_at_gps: Time.current.iso8601,
          latitude: 49.41, longitude: -103.62, gps_accuracy_m: 8,
          app_build: "phase2-rc1",
          client_uuid: "uuid-A",
          photo: photo
        }
      }, headers: { "Accept" => "application/json" }
    end
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "synced", body["status"]
    assert_equal 1, body["placements"].size
  end

  test "POST /api/catches is idempotent on client_uuid" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    payload = lambda {
      post "/api/catches", params: {
        catch: { species_id: @walleye.id, length_inches: 18, captured_at_device: Time.current.iso8601,
                 client_uuid: "uuid-DUP", photo: photo }
      }, headers: { "Accept" => "application/json" }
    }
    payload.call
    assert_no_difference "Catch.count" do
      payload.call
    end
    assert_response :ok
  end

  test "missing GPS flags catch as needs_review" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    post "/api/catches", params: {
      catch: { species_id: @walleye.id, length_inches: 12, captured_at_device: Time.current.iso8601,
               client_uuid: "uuid-NOGPS", photo: photo }
    }, headers: { "Accept" => "application/json" }
    body = JSON.parse(response.body)
    assert_equal "needs_review", body["status"]
    assert_includes body["flags"], "missing_gps"
  end

  test "clock skew > threshold flags as needs_review" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    now = Time.current
    post "/api/catches", params: {
      catch: { species_id: @walleye.id, length_inches: 12,
               captured_at_device: now.iso8601, captured_at_gps: (now - 10.minutes).iso8601,
               latitude: 49.0, longitude: -98.0, gps_accuracy_m: 5,
               client_uuid: "uuid-SKEW", photo: photo }
    }, headers: { "Accept" => "application/json" }
    assert_includes JSON.parse(response.body)["flags"], "clock_skew"
  end

  test "POST /api/catches persists note but does not echo it in response" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    post "/api/catches", params: {
      catch: {
        species_id: @walleye.id,
        length_inches: 18,
        captured_at_device: Time.current.iso8601,
        latitude: 49.0, longitude: -98.0, gps_accuracy_m: 5,
        client_uuid: "uuid-NOTE",
        photo: photo,
        note: "personal-secret-XYZ"
      }
    }, headers: { "Accept" => "application/json" }

    assert_response :created
    persisted = Catch.find_by(client_uuid: "uuid-NOTE")
    assert_equal "personal-secret-XYZ", persisted.note
    assert_not_includes response.body, "personal-secret-XYZ"
    assert_not_includes response.body, "note"
  end

  test "POST /api/catches persists the logged length_unit" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    post "/api/catches", params: {
      catch: {
        species_id: @walleye.id,
        length_inches: 14.47,
        length_unit: "centimeters",
        captured_at_device: Time.current.iso8601,
        latitude: 49.0, longitude: -98.0, gps_accuracy_m: 5,
        client_uuid: "uuid-CM",
        photo: photo
      }
    }, headers: { "Accept" => "application/json" }

    assert_response :created
    persisted = Catch.find_by(client_uuid: "uuid-CM")
    assert_equal "centimeters", persisted.length_unit
  end

  test "POST /api/catches persists flags on the catch record" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    post "/api/catches", params: {
      catch: { species_id: @walleye.id, length_inches: 12,
               captured_at_device: Time.current.iso8601,
               client_uuid: "uuid-PERSIST", photo: photo }
    }, headers: { "Accept" => "application/json" }
    persisted = Catch.find_by(client_uuid: "uuid-PERSIST")
    assert_includes persisted.flags, "missing_gps"
  end

  test "out-of-bounds GPS flags catch as needs_review" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    post "/api/catches", params: {
      catch: { species_id: @walleye.id, length_inches: 12,
               captured_at_device: Time.current.iso8601, captured_at_gps: Time.current.iso8601,
               latitude: 49.9, longitude: -97.1, gps_accuracy_m: 5,
               client_uuid: "uuid-OOB", photo: photo }
    }, headers: { "Accept" => "application/json" }
    body = JSON.parse(response.body)
    assert_equal "needs_review", body["status"]
    assert_includes body["flags"], "out_of_bounds"
  end

  test "POST /api/catches returns 401 once the user is deactivated" do
    @user.update!(deactivated_at: Time.current)
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    post "/api/catches", params: {
      catch: {
        species_id: @walleye.id,
        length_inches: 19.5,
        captured_at_device: Time.current.iso8601,
        client_uuid: "uuid-DEACT",
        photo: photo
      }
    }, headers: { "Accept" => "application/json" }
    assert_response :unauthorized
  end

  test "POST /api/catches clears the stale session when the user is deactivated" do
    @user.update!(deactivated_at: Time.current)
    post "/api/catches", params: {
      catch: { species_id: @walleye.id, length_inches: 19.5,
               captured_at_device: Time.current.iso8601, client_uuid: "uuid-DEACT2" }
    }, headers: { "Accept" => "application/json" }
    assert_response :unauthorized
    assert_nil session[:user_id], "deactivated user's session should be cleared, not left poisoned"
  end

  test "POST /api/catches with valid teammate files catch under teammate and stamps logger" do
    @tournament.update!(mode: :team)
    teammate = create(:user, club: @club, name: "Boatmate")
    entry = TournamentEntry.joins(:tournament_entry_members).find_by(tournament_entry_members: { user_id: @user.id })
    create(:tournament_entry_member, tournament_entry: entry, user: teammate)
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    now = Time.current

    post "/api/catches", params: {
      teammate_user_id: teammate.id,
      catch: {
        species_id: @walleye.id, length_inches: 18.5,
        captured_at_device: now.iso8601, captured_at_gps: now.iso8601,
        latitude: 49.41, longitude: -103.62,
        client_uuid: "uuid-team", photo: photo
      }
    }, headers: { "Accept" => "application/json" }
    assert_response :created
    persisted = Catch.find_by(client_uuid: "uuid-team")
    assert_equal teammate.id, persisted.user_id
    assert_equal @user.id, persisted.logged_by_user_id
  end

  test "POST /api/catches rejects teammate from another club" do
    other_club = create(:club)
    foreigner = create(:user, club: other_club)
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")

    assert_no_difference -> { Catch.count } do
      post "/api/catches", params: {
        teammate_user_id: foreigner.id,
        catch: {
          species_id: @walleye.id, length_inches: 18.5,
          captured_at_device: Time.current.iso8601,
          client_uuid: "uuid-foreign", photo: photo
        }
      }, headers: { "Accept" => "application/json" }
    end
    assert_response :unprocessable_entity
    assert_match "Teammate not found", response.body
  end

  test "POST /api/catches rejects teammate without a shared entry" do
    other_user = create(:user, club: @club)
    other_entry = create(:tournament_entry, tournament: @tournament)
    create(:tournament_entry_member, tournament_entry: other_entry, user: other_user)
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")

    assert_no_difference -> { Catch.count } do
      post "/api/catches", params: {
        teammate_user_id: other_user.id,
        catch: {
          species_id: @walleye.id, length_inches: 18.5,
          captured_at_device: Time.current.iso8601,
          client_uuid: "uuid-no-share", photo: photo
        }
      }, headers: { "Accept" => "application/json" }
    end
    assert_response :unprocessable_entity
    assert_match "aren't on the same entry", response.body
  end

  test "POST /api/catches is idempotent for retry of a teammate catch" do
    @tournament.update!(mode: :team)
    teammate = create(:user, club: @club)
    entry = TournamentEntry.joins(:tournament_entry_members).find_by(tournament_entry_members: { user_id: @user.id })
    create(:tournament_entry_member, tournament_entry: entry, user: teammate)

    payload = lambda {
      post "/api/catches", params: {
        teammate_user_id: teammate.id,
        catch: { species_id: @walleye.id, length_inches: 18.5,
                 captured_at_device: Time.current.iso8601,
                 client_uuid: "uuid-team-retry",
                 photo: fixture_file_upload("sample_walleye.jpg", "image/jpeg") }
      }, headers: { "Accept" => "application/json" }
    }
    payload.call
    assert_no_difference "Catch.count" do
      payload.call
    end
    assert_response :ok
  end

  test "POST /api/catches sets lake from GPS coordinates" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    assert_difference -> { Catch.count } => 1 do
      post "/api/catches", params: {
        catch: {
          species_id: @walleye.id,
          length_inches: 19.5,
          captured_at_device: Time.current.iso8601,
          captured_at_gps: Time.current.iso8601,
          latitude: 53.55, longitude: -103.65, gps_accuracy_m: 8,
          client_uuid: "uuid-lake-tobin",
          photo: photo
        }
      }, headers: { "Accept" => "application/json" }
    end
    assert_response :created
    assert_equal "tobin", Catch.find_by(client_uuid: "uuid-lake-tobin").lake
  end

  test "persists tag_number on a Tagged Walleye catch" do
    tagged = Species.find_or_create_by!(name: "Tagged Walleye")
    uuid = SecureRandom.uuid

    post "/api/catches", params: {
      catch: {
        species_id: tagged.id,
        length_inches: 18.5,
        captured_at_device: 1.minute.ago.iso8601,
        client_uuid: uuid,
        tag_number: "a1234",
        photo: fixture_file_upload("sample_walleye.jpg", "image/jpeg")
      }
    }, headers: { "Accept" => "application/json" }

    assert_response :created
    catch_record = Catch.find_by(client_uuid: JSON.parse(response.body).fetch("client_uuid"))
    assert_equal "A1234", catch_record.tag_number
  end

  test "persists weight_text on a Tagged Walleye catch" do
    tagged = Species.find_or_create_by!(name: "Tagged Walleye")
    uuid = SecureRandom.uuid

    post "/api/catches", params: {
      catch: {
        species_id: tagged.id,
        length_inches: 18.5,
        captured_at_device: 1.minute.ago.iso8601,
        client_uuid: uuid,
        tag_number: "A1234",
        weight_text: "4 lbs 3oz",
        photo: fixture_file_upload("sample_walleye.jpg", "image/jpeg")
      }
    }, headers: { "Accept" => "application/json" }

    assert_response :created
    catch_record = Catch.find_by(client_uuid: JSON.parse(response.body).fetch("client_uuid"))
    assert_equal "4 lbs 3oz", catch_record.weight_text
  end

  test "accepts blank weight_text on a Tagged Walleye catch" do
    tagged = Species.find_or_create_by!(name: "Tagged Walleye")
    uuid = SecureRandom.uuid

    post "/api/catches", params: {
      catch: {
        species_id: tagged.id,
        length_inches: 18.5,
        captured_at_device: 1.minute.ago.iso8601,
        client_uuid: uuid,
        tag_number: "A1234",
        photo: fixture_file_upload("sample_walleye.jpg", "image/jpeg")
      }
    }, headers: { "Accept" => "application/json" }

    assert_response :created
    assert_nil Catch.find_by(client_uuid: uuid).weight_text
  end

  # WebKit can send a request with NO body at all when it fails to stream a
  # file-backed IndexedDB blob (the 2026-07-15 incident: 595 empty-bodied
  # 400s). Rails' default ParameterMissing response is an HTML page, which
  # sync.js can't parse — the angler saw "{}" as the failure reason. The API
  # must answer with readable JSON so the pending-catches widget can show
  # something actionable.
  test "POST /api/catches with an empty body returns readable JSON 400" do
    post "/api/catches", params: {}, headers: { "Accept" => "application/json" }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_kind_of Array, body["errors"]
    assert_match(/empty/i, body["errors"].join(", "))
  end

  # Regression lock: Api::CatchesController#create calls save BEFORE its
  # photo.attached? check — only the model's photo_must_be_attached validation
  # stops a photo-less row from persisting. If that validation is ever removed,
  # a photo-less 422 would leave a row behind and the client_uuid retry would
  # return 200 for a catch with no photo (poisoned idempotency, catch never
  # placed). These two tests keep that from regressing silently.
  test "POST /api/catches without a photo persists no row" do
    assert_no_difference "Catch.count" do
      post "/api/catches", params: {
        catch: { species_id: @walleye.id, length_inches: 18,
                 captured_at_device: Time.current.iso8601, client_uuid: "uuid-NOPHOTO" }
      }, headers: { "Accept" => "application/json" }
    end
    assert_response :unprocessable_entity
    assert_match(/photo/i, JSON.parse(response.body)["errors"].join(", "))
  end

  test "retry with photo succeeds after a photo-less attempt with the same client_uuid" do
    post "/api/catches", params: {
      catch: { species_id: @walleye.id, length_inches: 18,
               captured_at_device: Time.current.iso8601, client_uuid: "uuid-RETRY-PHOTO" }
    }, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity

    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    assert_difference "Catch.count", 1 do
      post "/api/catches", params: {
        catch: { species_id: @walleye.id, length_inches: 18,
                 captured_at_device: Time.current.iso8601,
                 client_uuid: "uuid-RETRY-PHOTO", photo: photo }
      }, headers: { "Accept" => "application/json" }
    end
    assert_response :created
    assert Catch.find_by(client_uuid: "uuid-RETRY-PHOTO").photo.attached?
  end

  test "dedup retry places a saved-but-unplaced catch (post-500 recovery)" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    payload = lambda {
      post "/api/catches", params: {
        catch: { species_id: @walleye.id, length_inches: 20, captured_at_device: Time.current.iso8601,
                 client_uuid: "uuid-RECONCILE", photo: photo }
      }, headers: { "Accept" => "application/json" }
    }
    payload.call
    catch_record = Catch.find_by!(client_uuid: "uuid-RECONCILE")
    # Simulate the crash window: catch committed, PlaceInSlots' transaction rolled back.
    catch_record.catch_placements.destroy_all

    assert_difference "CatchPlacement.count", 1 do
      payload.call
    end
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 1, body["placements"].size
  end

  test "dedup retry does NOT double-place a catch that already has placements" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    payload = lambda {
      post "/api/catches", params: {
        catch: { species_id: @walleye.id, length_inches: 20, captured_at_device: Time.current.iso8601,
                 client_uuid: "uuid-NODOUBLE", photo: photo }
      }, headers: { "Accept" => "application/json" }
    }
    payload.call
    assert_no_difference "CatchPlacement.count" do
      payload.call
    end
    assert_response :ok
  end

  test "dedup response reports the catch's real flags" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    payload = lambda {
      post "/api/catches", params: {
        catch: { species_id: @walleye.id, length_inches: 20, captured_at_device: Time.current.iso8601,
                 client_uuid: "uuid-FLAGS", photo: photo } # no GPS -> missing_gps flag
      }, headers: { "Accept" => "application/json" }
    }
    payload.call
    payload.call
    assert_response :ok
    assert_includes JSON.parse(response.body)["flags"], "missing_gps"
  end

  test "teammate submission with no active club membership returns 422, not 500" do
    @user.club_memberships.destroy_all
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    post "/api/catches", params: {
      teammate_user_id: 999_999,
      catch: { species_id: @walleye.id, length_inches: 20, captured_at_device: Time.current.iso8601,
               client_uuid: "uuid-NOCLUB", photo: photo }
    }, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
