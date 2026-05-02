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

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
