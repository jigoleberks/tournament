require "application_system_test_case"

# The release-video recorder must fail GRACEFULLY when the camera is denied.
# Every MediaRecorder-support failure already routes through markFailed() —
# which sets data-captured="failed" and dispatches the failed event the catch
# form listens for — but a getUserMedia rejection (permission denied, no
# camera) used to throw out of start() before that safety net, wedging the
# video UI with no signal to the form.
class VideoCaptureTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Joe")
    @walleye = create(:species, club: @club, name: "Walleye")
    @tournament = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                         requires_release_video: true)
    create(:scoring_slot, tournament: @tournament, species: @walleye, slot_count: 2)
    entry = create(:tournament_entry, tournament: @tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)
  end

  test "denied camera permission marks the video failed instead of wedging" do
    sign_in_as(@user)

    apply_ios_shims(deny_camera: true)

    visit "/catches/new"
    assert_button "Start recording"
    click_button "Start recording"

    assert_selector "[data-video-capture-target='preview'][data-captured='failed']",
                    visible: :all, wait: 5
  end
end
