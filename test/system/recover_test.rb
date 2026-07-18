require "application_system_test_case"

# /recover re-materializes a stuck IndexedDB photo blob and re-submits it.
# See docs/superpowers/specs/2026-07-16-ios-blob-sync-fix-design.md.
class RecoverTest < ApplicationSystemTestCase
  setup do
    @club = create(:club, recovery_tool_enabled: true)
    @user = create(:user, club: @club, name: "Joe")
    @walleye = create(:species, club: @club, name: "Walleye")
  end

  test "re-materializes a stuck photo and re-submits it as a real catch" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    seed_catch(uuid: uuid)
    visit "/recover"

    assert_selector "li img", wait: 5           # thumbnail => blob re-materialized
    click_button "Re-submit"

    catch_record = nil
    Timeout.timeout(15) do
      loop do
        catch_record = Catch.find_by(client_uuid: uuid)
        break if catch_record
        sleep 0.2
      end
    end
    assert catch_record, "expected /recover to re-submit the stuck catch"
    assert_equal @user.id, catch_record.user_id
    assert_equal 18, catch_record.length_inches.to_i
    assert_selector "button", text: "Recovered", wait: 5
  end

  # Turbo Drive caches the DOM snapshot of a page when you navigate away from
  # it, and restores that snapshot verbatim (including whatever the JS had
  # already rendered into it) on a back-navigation. connect() then runs again
  # on top of the restored rows. Capybara's `visit` is a full browser
  # navigation, not a Turbo visit, and does not populate Turbo's snapshot
  # cache — so getting a real restore requires leaving via a Turbo-driven
  # link (the bottom-nav Home icon) and then going back.
  test "a Turbo restore visit does not duplicate rows" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    seed_catch(uuid: uuid)
    visit "/recover"
    assert_selector "li", count: 1, wait: 5

    find("a[aria-label='Home']").click
    assert_text "Hello, #{@user.name}", wait: 5

    page.go_back
    # NOTE: connect() re-renders rows asynchronously (each row awaits
    # rematerialize() before appending its <li>). A plain
    # `assert_selector "li", count: 1, wait: 5` is NOT safe here — Capybara's
    # polling matcher returns as soon as it FIRST observes the target count,
    # so it can (and did, before this helper) pass by sampling the DOM before
    # the duplicate row has finished appending. We instead wait for the <li>
    # count to stop changing, then assert on the settled value.
    assert_equal 1, stable_li_count
  end

  # iOS restores /recover from the bfcache with whatever CSRF meta token the
  # page was first rendered with; re-submitting with it fails on every tap
  # until a hard reload — on the tool of last resort. resubmit() therefore
  # preflights GET /api/session (same pattern as offline/sync.js) for a fresh
  # token. The stale-token 422 itself can't be reproduced here (test env
  # disables forgery protection, and with it the csrf meta tag), so this locks
  # in the preflight behaviorally: a dead session must halt with a sign-in
  # message BEFORE any photo-body POST is attempted.
  test "re-submit preflights the session and halts with a sign-in message on 401" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    seed_catch(uuid: uuid)
    visit "/recover"
    assert_selector "li img", wait: 5

    page.execute_script <<~JS
      const realFetch = window.fetch.bind(window);
      window.__catchPosts = 0;
      window.fetch = (input, init = {}) => {
        const url = String(input.url || input);
        if (url.includes("/api/session")) {
          return Promise.resolve(new Response("{}", { status: 401, headers: { "Content-Type": "application/json" } }));
        }
        if (url.includes("/api/catches")) window.__catchPosts++;
        return realFetch(input, init);
      };
    JS
    click_button "Re-submit"

    assert_text(/signed out.*sign in/i, wait: 5)
    assert_equal 0, page.evaluate_script("window.__catchPosts"),
                 "a dead session must halt resubmit before the photo-body POST"
    assert_nil Catch.find_by(client_uuid: uuid)
    assert_selector "button", text: "Retry"
  end

  test "the home link appears only when the angler has stuck catches" do
    sign_in_as(@user)
    visit root_path
    assert_no_selector "[data-pending-catches-target='recoverLink']", visible: true

    seed_catch(uuid: SecureRandom.uuid)
    visit root_path
    assert_selector "[data-pending-catches-target='recoverLink']", visible: true, wait: 5
  end

  test "the home link appears for a pending-stuck catch, not just failed ones" do
    sign_in_as(@user)
    visit root_path
    assert_no_selector "[data-pending-catches-target='recoverLink']", visible: true

    # Queued long enough ago to be stuck rather than in-flight. The age is what
    # makes this the pending-STUCK case: seeded at Date.now() it would be
    # indistinguishable from a catch that is simply mid-upload.
    seed_catch(uuid: SecureRandom.uuid, status: "pending", queued_ago_ms: 10 * 60 * 1000)
    # Re-render the widget without firing drain() (which would upload the record
    # and empty the pending bucket). The controller refreshes on this event.
    page.execute_script("window.dispatchEvent(new CustomEvent('bsfamilies:catch-failed', { detail: {} }))")
    assert_selector "[data-pending-catches-target='recoverLink']", visible: true, wait: 5
  end

  # The complement of the test above, and the reason the age check exists: a
  # catch queued a moment ago is just syncing. Offering "Recover these with
  # photos" for the second or two drain() takes trains anglers to reach for the
  # recovery tool during perfectly healthy operation.
  test "the home link stays hidden for a catch that is merely mid-upload" do
    sign_in_as(@user)
    visit root_path

    seed_catch(uuid: SecureRandom.uuid, status: "pending", queued_ago_ms: 0)
    page.execute_script("window.dispatchEvent(new CustomEvent('bsfamilies:catch-failed', { detail: {} }))")
    # The widget re-renders on that event; wait for the pending row to prove the
    # render happened, so the link assertion isn't just winning a race.
    assert_selector "[data-pending-catches-target='list'] li", wait: 5
    assert_no_selector "[data-pending-catches-target='recoverLink']", visible: true
  end

  private

  # Waits until the <li> count under data-recover-target=list hasn't changed
  # for `settle` seconds, then returns it. connect() renders rows one at a
  # time (each awaiting an async rematerialize), so a single-sample count can
  # catch the DOM mid-render; this waits it out instead.
  def stable_li_count(settle: 1.0, timeout: 6)
    last = page.all("li", minimum: 0).size
    stable_since = Time.now
    Timeout.timeout(timeout) do
      loop do
        current = page.all("li", minimum: 0).size
        if current != last
          last = current
          stable_since = Time.now
        end
        break if Time.now - stable_since >= settle
        sleep 0.1
      end
    end
    last
  end

  def sign_in_as(user)
    SignInToken.issue!(user: user)
    visit consume_session_path(token: SignInToken.last.token)
  end

  # queued_ago_ms backdates queued_at, which is what the widget uses to tell a
  # stuck pending catch from one that is merely mid-upload.
  def seed_catch(uuid:, status: "failed", queued_ago_ms: 0)
    page.execute_script <<~JS
      window.__seeded = false;
      (async () => {
        const dbReq = indexedDB.open("bsfamilies", 1);
        const db = await new Promise((res, rej) => {
          dbReq.onupgradeneeded = (e) => {
            const d = e.target.result;
            if (!d.objectStoreNames.contains("catches")) {
              const s = d.createObjectStore("catches", { keyPath: "client_uuid" });
              s.createIndex("status", "status");
            }
          };
          dbReq.onsuccess = (e) => res(e.target.result);
          dbReq.onerror   = (e) => rej(e);
        });
        const photo = new Blob([new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0])], { type: "image/jpeg" });
        const tx = db.transaction("catches", "readwrite");
        tx.objectStore("catches").put({
          client_uuid: "#{uuid}",
          species_id: "#{@walleye.id}",
          length_inches: "18",
          length_unit: "inches",
          captured_at_device: new Date().toISOString(),
          photo: photo,
          status: "#{status}",
          reason: "test",
          queued_at: Date.now() - #{queued_ago_ms}
        });
        await new Promise((res, rej) => { tx.oncomplete = res; tx.onerror = rej; });
        window.__seeded = true;
      })().catch((err) => { window.__seedError = String(err); });
    JS

    Timeout.timeout(5) do
      loop do
        break if page.evaluate_script("window.__seeded === true")
        err = page.evaluate_script("window.__seedError || null")
        flunk "IDB seeding errored: #{err}" if err
        sleep 0.1
      end
    end
  end
end
