require "test_helper"

class CatchesControllerJudgeTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @walleye = create(:species, club: @club)
    @tournament = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: @tournament, species: @walleye, slot_count: 2)
    @entry = create(:tournament_entry, tournament: @tournament)
    create(:tournament_entry_member, tournament_entry: @entry, user: @user)

    # the user is also a judge for this tournament
    create(:tournament_judge, tournament: @tournament, user: @user)

    sign_in_as(@user)
  end

  test "catch is created but is NOT placed in tournaments where the user is a judge" do
    photo = fixture_file_upload("sample_walleye.jpg", "image/jpeg")
    assert_difference "Catch.count", 1 do
      post catches_path, params: {
        catch: {
          species_id: @walleye.id, length_inches: 19, captured_at_device: Time.current,
          client_uuid: "uuid-judge", photo: photo
        }
      }
    end
    assert_equal 0, CatchPlacement.where(tournament: @tournament).count
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
