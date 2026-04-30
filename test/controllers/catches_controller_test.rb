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

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
