require "application_system_test_case"

# A logged fish must never be destroyable from the device: an unsynced catch is
# the ONLY copy of its photo. On 2026-07-15 a Dismiss tap would have destroyed
# six real photos that turned out to be perfectly intact.
class PendingCatchesTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Joe")
    @walleye = create(:species, club: @club, name: "Walleye")
  end

  test "a failed catch offers no way to delete it and survives a refresh" do
    seed_failed_catch(uuid: SecureRandom.uuid)

    visit root_path
    assert_selector "[data-pending-catches-target='failedList'] li", wait: 5
    assert_selector "button", text: "Retry"
    assert_no_selector "button", text: "Dismiss"

    visit root_path
    assert_selector "[data-pending-catches-target='failedList'] li", wait: 5,
                    count: 1
  end

  # sync.js stores a human-readable reason on every failure but nothing has ever
  # rendered it, so anglers saw a bare "⚠️ 18″" with no idea what went wrong.
  test "a failed catch shows why it failed" do
    seed_failed_catch(uuid: SecureRandom.uuid,
                      reason: "Photo could not be read from this device")

    visit root_path
    assert_text "Photo could not be read from this device", wait: 5
  end

  test "a failure reason is escaped, not injected as markup" do
    seed_failed_catch(uuid: SecureRandom.uuid, reason: "<img src=x onerror=alert(1)>boom")

    visit root_path
    assert_text "boom", wait: 5
    assert_no_selector "[data-pending-catches-target='failedList'] img"
  end

  # A catch the server 5xx'd is held back by deferRetry for up to 15 minutes.
  # Rendered as a bare 🕐 it was indistinguishable from a healthy in-flight
  # upload, and the Retry button existed only for FAILED records — so an angler
  # watching a fish miss the leaderboard had no way to see why, or to hurry it.
  test "a catch parked in upload backoff says so and can be retried" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    seed_idb_catch(uuid: uuid, species_id: @walleye.id, trigger_js: "void 0",
                   extra_fields: { next_attempt_at: "Date.now() + 900000", attempts: 5 })

    visit root_path
    assert_text "Upload didn’t go through", wait: 5
    assert_selector "[data-pending-catches-target='list'] button", text: "Retry"

    find("[data-pending-catches-target='list'] button", text: "Retry").click
    Timeout.timeout(15) do
      sleep 0.2 until Catch.find_by(client_uuid: uuid)
    end
  end

  # The test above seeds a record that is ALREADY parked and then loads the
  # page, so connect() renders the notice. The angler's real case is the
  # opposite order: they are already sitting on the page when the drain 5xx's
  # and parks the catch. deferRetry dispatched no event, and this controller
  # only re-renders on catch-synced/catch-failed, so the row stayed a bare 🕐
  # for the whole 15-minute backoff — the exact state the notice exists for.
  test "a catch parked while the angler is watching updates the widget in place" do
    sign_in_as(@user)
    visit root_path
    assert_selector "[data-controller='pending-catches']", wait: 5

    page.execute_script <<~JS
      const realFetch = window.fetch;
      window.fetch = (url, opts) => {
        if (String(url).includes("/api/catches")) {
          return Promise.resolve(new Response("boom", { status: 500 }));
        }
        return realFetch(url, opts);
      };
    JS

    seed_idb_catch(uuid: SecureRandom.uuid, species_id: @walleye.id,
                   trigger_js: "window.dispatchEvent(new Event('bsfamilies:try-sync'))")

    # No revisit: the widget must react to the parking itself.
    assert_text "Upload didn’t go through", wait: 10
    assert_selector "[data-pending-catches-target='list'] button", text: "Retry"
  end

  private

  def sign_in_as(user)
    SignInToken.issue!(user: user)
    visit consume_session_path(token: SignInToken.last.token)
  end

  def seed_failed_catch(uuid:, reason: "test")
    sign_in_as(@user)
    page.execute_script <<~JS
      window.__seeded = false;
      (async () => {
        const dbReq = indexedDB.open("bsfamilies", 2);
        const db = await new Promise((res, rej) => {
          dbReq.onupgradeneeded = (e) => {
            const d = e.target.result;
            if (!d.objectStoreNames.contains("catches")) {
              const s = d.createObjectStore("catches", { keyPath: "client_uuid" });
              s.createIndex("status", "status");
            }
            if (!d.objectStoreNames.contains("blobs")) {
              d.createObjectStore("blobs", { keyPath: "client_uuid" });
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
          status: "failed",
          reason: #{reason.to_json},
          queued_at: Date.now()
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
