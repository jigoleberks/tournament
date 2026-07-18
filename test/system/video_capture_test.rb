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

  # iOS kills the capture session on a phone call, screen lock, app switch, or
  # when the native photo sheet opens. The recorder then stops with zero chunks
  # — which used to be treated as a successful capture: the form submitted with
  # a 0-byte video that _packBlob silently dropped, and the catch arrived
  # video_missing-flagged while the angler believed they recorded it.
  test "an interrupted recording that yields zero bytes is treated as failed, not captured" do
    sign_in_as(@user)

    apply_ios_shims(extra_js: <<~JS)
      Object.defineProperty(navigator, "mediaDevices", {
        configurable: true,
        value: { getUserMedia: () => Promise.resolve(new MediaStream()) }
      });
      window.MediaRecorder = class {
        static isTypeSupported() { return true }
        constructor(_stream, opts) { this.state = "inactive"; this.mimeType = opts.mimeType }
        start() { this.state = "recording" }
        stop() { this.state = "inactive"; if (this.onstop) this.onstop() }
      };
      HTMLMediaElement.prototype.play = function () { return Promise.resolve() };
    JS

    visit "/catches/new"
    click_button "Start recording"
    click_button "Stop"

    assert_text(/recording failed/i, wait: 5)
    assert_selector "[data-video-capture-target='preview'][data-captured='failed']",
                    visible: :all, wait: 5
  end

  # The double-tap guard used to check this.recorder, which isn't created until
  # AFTER the getUserMedia await resolves — and on first use iOS holds that
  # await open for seconds behind the permission prompt. Two taps in that
  # window ran two getUserMedia calls; the first stream was orphaned unstopped
  # (camera indicator pinned; iOS's single-capture-session rule can wedge the
  # camera until the tab dies).
  test "double-tapping Start during camera warm-up acquires only one stream" do
    sign_in_as(@user)

    apply_ios_shims(extra_js: <<~JS)
      window.__gumCalls = 0;
      Object.defineProperty(navigator, "mediaDevices", {
        configurable: true,
        value: {
          getUserMedia: () => {
            window.__gumCalls++;
            return new Promise((res) => setTimeout(() => res(new MediaStream()), 300));
          }
        }
      });
      window.MediaRecorder = class {
        static isTypeSupported() { return true }
        constructor(_stream, opts) { this.state = "inactive"; this.mimeType = opts.mimeType }
        start() { this.state = "recording" }
        stop() { this.state = "inactive"; if (this.onstop) this.onstop() }
      };
      HTMLMediaElement.prototype.play = function () { return Promise.resolve() };
    JS

    visit "/catches/new"
    click_button "Start recording"
    click_button "Start recording"
    sleep 0.6

    assert_equal 1, page.evaluate_script("window.__gumCalls"),
                 "a second tap during the getUserMedia await must not start a second acquisition"
  end
end
