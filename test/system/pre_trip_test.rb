require "application_system_test_case"

class PreTripTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
  end

  test "pre-trip page shows checks" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit pre_trip_path

    assert_text "Pre-trip check"
    assert_selector "[data-check='session']"
    assert_selector "[data-check='camera']"
    assert_selector "[data-check='gps']"
    assert_selector "[data-check='clock']"
    assert_selector "[data-check='notifications']"
    assert_selector "[data-check='network']"
  end

  test "pre-trip page shows the app version row, up to date with the server build" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit pre_trip_path

    # On a fresh load there is no stale cached shell, so the row settles on the
    # up-to-date state and surfaces the current server build id.
    assert_selector "[data-check='version']"
    assert_selector "[data-pre-trip-target='version']", text: "✓"
    assert_selector "[data-pre-trip-target='version']", text: AppVersion.current[0, 7]
  end

  test "Re-test pings the server and flags an update when the loaded build is behind" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit pre_trip_path
    assert_selector "[data-pre-trip-target='version']", text: "✓"

    # Simulate a phone still showing a page rendered before a deploy: rewrite the
    # build baked into the loaded page, then re-run the checks. The server (via
    # /api/version) still reports the real current build, so the row must flag it.
    page.execute_script("document.documentElement.dataset.appBuild = '0000000'")
    click_button "Re-test"

    assert_selector "[data-pre-trip-target='version']", text: "⚠ update available"
    assert_selector "[data-pre-trip-target='version']", text: "0000000"
    assert_selector "[data-pre-trip-target='version']", text: AppVersion.current[0, 7]
    assert_selector "[data-check='version'] [data-pre-trip-hint]", text: "Update app (clear cache)"
  end

  test "a passing check shows no hint" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit pre_trip_path

    # The session row can't fail — the page requires sign-in to reach.
    assert_selector "[data-pre-trip-target='session']", text: "✓"
    assert_no_selector "[data-check='session'] [data-pre-trip-hint]"
  end

  test "Re-test clears a stale hint once the failing check starts passing" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit pre_trip_path

    # The version row is the last check to settle, so this waits out the entire
    # page-load run. Stubbing before it finishes lets the old run's late
    # callbacks overwrite the stubbed run's rows.
    assert_selector "[data-pre-trip-target='version']", text: /✓|⚠|ℹ/

    # Force the camera check to fail: stub getUserMedia to reject like a real
    # browser would when the camera errors out, then Re-test to produce a
    # visible hint under the camera row.
    page.execute_script(<<~JS)
      navigator.mediaDevices.getUserMedia = () => Promise.reject(new DOMException("fail", "NotFoundError"))
    JS
    click_button "Re-test"

    assert_selector "[data-pre-trip-target='camera']", text: "✗"
    assert_selector "[data-check='camera'] [data-pre-trip-hint]", text: "no rear camera"

    # Now make the same check pass and Re-test again. The row must flip to ✓
    # AND the hint paragraph left over from the failing run must be cleared —
    # this is the stale-hint-clearing path the earlier "no hint" test can't
    # reach, since that test's check (session) never fails in the first place.
    page.execute_script(<<~JS)
      navigator.mediaDevices.getUserMedia = () => Promise.resolve({ getTracks: () => [] })
    JS
    click_button "Re-test"

    assert_selector "[data-pre-trip-target='camera'].text-emerald-400", text: "✓"
    assert_no_selector "[data-check='camera'] [data-pre-trip-hint]"
  end

  test "the session check renders green and the version check renders green" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit pre_trip_path

    assert_selector "[data-pre-trip-target='session'].text-emerald-400"
    assert_selector "[data-pre-trip-target='version'].text-emerald-400"
  end
end

class PreTripNoTournamentTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    # Deliberately no tournament: this is the normal state on most days.
  end

  test "no active tournament renders blue, not amber, and explains itself" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit pre_trip_path

    assert_selector "[data-pre-trip-target='tournaments'].text-blue-300", text: "ℹ no active tournaments today"
    assert_selector "[data-check='tournaments'] [data-pre-trip-hint]", text: "won't score until a tournament is running"
  end
end

class PreTripCameraCauseTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit pre_trip_path
    # The version row is the last check to settle, so this waits out the entire
    # page-load run. Stubbing before it finishes lets the old run's late
    # callbacks overwrite the stubbed run's rows.
    assert_selector "[data-pre-trip-target='version']", text: /✓|⚠|ℹ/
  end

  # Rejects getUserMedia with the named DOMException, then re-runs the checks.
  def rerun_with_media_error(name)
    page.execute_script(<<~JS)
      navigator.mediaDevices.getUserMedia = () =>
        Promise.reject(new DOMException("stubbed", "#{name}"))
    JS
    click_button "Re-test"
  end

  test "a denied camera permission says how to unblock it" do
    rerun_with_media_error("NotAllowedError")

    assert_selector "[data-pre-trip-target='camera'].text-red-400", text: "✗ blocked"
    assert_selector "[data-check='camera'] [data-pre-trip-hint]", text: "set Camera to Allow"
  end

  test "a missing camera says to use a phone, not to change permissions" do
    rerun_with_media_error("NotFoundError")

    assert_selector "[data-pre-trip-target='camera']", text: "✗ no camera found"
    assert_selector "[data-check='camera'] [data-pre-trip-hint]", text: "no rear camera"
  end

  test "a busy camera says to close the other app" do
    rerun_with_media_error("NotReadableError")

    assert_selector "[data-pre-trip-target='camera']", text: "✗ camera busy"
    assert_selector "[data-check='camera'] [data-pre-trip-hint]", text: "Another app is using the camera"
  end

  test "the microphone reports its own cause and says photo catches still work" do
    rerun_with_media_error("NotFoundError")

    assert_selector "[data-pre-trip-target='microphone']", text: "✗ no microphone found"
    assert_selector "[data-check='microphone'] [data-pre-trip-hint]", text: "only video catches need one"
  end
end

class PreTripGpsCauseTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit pre_trip_path
    # The version row is the last check to settle, so this waits out the entire
    # page-load run. Stubbing before it finishes lets the old run's late
    # callbacks overwrite the stubbed run's rows.
    assert_selector "[data-pre-trip-target='version']", text: /✓|⚠|ℹ/
  end

  # Replaces getCurrentPosition with one that succeeds at the given accuracy and
  # timestamp, then re-runs the checks. skew_ms shifts the GPS clock away from
  # the phone's clock.
  def rerun_with_fix(accuracy:, skew_ms: 0)
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "geolocation", {
        configurable: true,
        value: {
          getCurrentPosition: (ok) => ok({
            coords: { accuracy: #{accuracy} },
            timestamp: Date.now() - #{skew_ms},
          }),
        },
      })
    JS
    click_button "Re-test"
  end

  # Replaces getCurrentPosition with one that fails with the given PositionError
  # code (1 = denied, 2 = unavailable, 3 = timeout).
  def rerun_with_position_error(code)
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "geolocation", {
        configurable: true,
        value: { getCurrentPosition: (ok, fail) => fail({ code: #{code} }) },
      })
    JS
    click_button "Re-test"
  end

  test "a denied location says to unblock it, not to step outside" do
    rerun_with_position_error(1)

    assert_selector "[data-pre-trip-target='gps'].text-red-400", text: "✗ blocked"
    assert_selector "[data-check='gps'] [data-pre-trip-hint]", text: "Allow location in your browser's site settings"
  end

  test "an unavailable fix says to cycle Location Services" do
    rerun_with_position_error(2)

    assert_selector "[data-pre-trip-target='gps'].text-red-400", text: "✗ no fix"
    assert_selector "[data-check='gps'] [data-pre-trip-hint]", text: "Turn Location Services off and back on"
  end

  test "a timed-out fix reports the timeout, not a denial" do
    rerun_with_position_error(3)

    assert_selector "[data-pre-trip-target='gps'].text-red-400", text: "✗ no fix (timeout)"
    assert_selector "[data-check='gps'] [data-pre-trip-hint]", text: "No fix within 8 seconds"
  end

  test "a failed fix leaves the clock check unable to run, and says so" do
    rerun_with_position_error(2)

    assert_selector "[data-pre-trip-target='clock'].text-amber-300", text: "⚠ no GPS clock"
    assert_selector "[data-check='clock'] [data-pre-trip-hint]", text: "Fix GPS above"
  end

  test "a good fix is green and carries no hint" do
    rerun_with_fix(accuracy: 12)

    assert_selector "[data-pre-trip-target='gps'].text-emerald-400", text: "✓ 12m"
    assert_no_selector "[data-check='gps'] [data-pre-trip-hint]"
  end

  test "a low-accuracy fix warns that the catch may be flagged" do
    rerun_with_fix(accuracy: 120)

    assert_selector "[data-pre-trip-target='gps'].text-amber-300", text: "⚠ 120m (low)"
    assert_selector "[data-check='gps'] [data-pre-trip-hint]", text: "may be flagged for judge review"
  end

  test "a very inaccurate fix fails rather than warns" do
    rerun_with_fix(accuracy: 400)

    assert_selector "[data-pre-trip-target='gps'].text-red-400", text: "✗ 400m"
    assert_selector "[data-check='gps'] [data-pre-trip-hint]", text: "Too imprecise to place a catch"
  end

  test "a skewed clock names the judge-review consequence and the fix" do
    rerun_with_fix(accuracy: 12, skew_ms: 12 * 60 * 1000)

    assert_selector "[data-pre-trip-target='clock'].text-red-400", text: "✗ 12m skew (> 5)"
    assert_selector "[data-check='clock'] [data-pre-trip-hint]", text: "Date & Time"
  end

  test "a clock within tolerance is green and carries no hint" do
    rerun_with_fix(accuracy: 12, skew_ms: 2000)

    assert_selector "[data-pre-trip-target='clock'].text-emerald-400", text: "✓"
    assert_no_selector "[data-check='clock'] [data-pre-trip-hint]"
  end

  test "the generation guard drops a stale run's late GPS callback" do
    # Stub a slow, bad fix — a GPS lock can take up to 8s on a real phone — and
    # kick off a Re-test, but don't wait for it to finish. Its checkGps promise
    # is now pending inside the setTimeout below.
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "geolocation", {
        configurable: true,
        value: {
          getCurrentPosition: (ok) => setTimeout(() => ok({
            coords: { accuracy: 400 },
            timestamp: Date.now(),
          }), 1500),
        },
      })
    JS
    click_button "Re-test"

    # Before that slow callback can fire, re-stub with an instant good fix and
    # Re-test again. This starts a second run (a new generation) while the
    # first run is still awaiting its setTimeout.
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "geolocation", {
        configurable: true,
        value: {
          getCurrentPosition: (ok) => ok({
            coords: { accuracy: 12 },
            timestamp: Date.now(),
          }),
        },
      })
    JS
    click_button "Re-test"

    assert_selector "[data-pre-trip-target='gps'].text-emerald-400", text: "✓ 12m"

    # Wait out the first (stale) run's 1500ms callback. Without the generation
    # guard in set(), this late write isn't dropped — it lands after the
    # second run has already finished and clobbers the gps row with the first
    # run's "✗ 400m" result, even though the fast, current run already
    # reported a good fix. That clobber is exactly what the guard prevents.
    sleep 2

    assert_selector "[data-pre-trip-target='gps'].text-emerald-400", text: "✓ 12m"
    assert_no_selector "[data-pre-trip-target='gps'].text-red-400"
    assert_no_text "400m"
  end
end
