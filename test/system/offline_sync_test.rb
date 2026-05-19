require "application_system_test_case"

# Locks in the iOS-friendly drain triggers in app/javascript/offline/sync.js.
# A queued catch in IndexedDB must upload when:
#   - visibilitychange fires with the document visible (foregrounding the PWA)
#   - bsfamilies:try-sync fires (manual retry from the pending-catches widget)
#
# Background: on 2026-05-13 a tournament called the wrong winner because an
# iOS Safari catch sat stuck-pending until the angler went home and reopened
# his phone — iOS has no Background Sync API, so the page must be alive to
# drain. Losing any of these triggers re-opens that incident.
class OfflineSyncTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Joe")
    @walleye = create(:species, club: @club, name: "Walleye")
  end

  test "pending IndexedDB catch uploads when visibilitychange fires" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    seed_pending_catch_and_trigger(uuid: uuid, trigger_js: "document.dispatchEvent(new Event('visibilitychange'))")
    assert_catch_received(uuid)
  end

  test "pending IndexedDB catch uploads when bsfamilies:try-sync fires" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    seed_pending_catch_and_trigger(uuid: uuid, trigger_js: "window.dispatchEvent(new Event('bsfamilies:try-sync'))")
    assert_catch_received(uuid)
  end

  private

  def sign_in_as(user)
    SignInToken.issue!(user: user)
    visit consume_session_path(token: SignInToken.last.token)
  end

  # Inserts a pending-status row into the bsfamilies IndexedDB store with a
  # tiny synthetic JPEG, then fires the supplied JS to trigger drain().
  # Polls window.__seeded so the Ruby side knows the JS finished before we
  # start polling the server.
  def seed_pending_catch_and_trigger(uuid:, trigger_js:)
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
          captured_at_device: new Date().toISOString(),
          photo: photo,
          status: "pending",
          queued_at: Date.now()
        });
        await new Promise((res, rej) => { tx.oncomplete = res; tx.onerror = rej; });
        #{trigger_js};
        window.__seeded = true;
      })().catch((err) => { window.__seedError = String(err); });
    JS

    Timeout.timeout(5) do
      loop do
        seeded = page.evaluate_script("window.__seeded === true")
        break if seeded
        err = page.evaluate_script("window.__seedError || null")
        flunk "IDB seeding errored: #{err}" if err
        sleep 0.1
      end
    end
  end

  def assert_catch_received(uuid)
    catch_record = nil
    Timeout.timeout(15) do
      loop do
        catch_record = Catch.find_by(client_uuid: uuid)
        break if catch_record
        sleep 0.2
      end
    end

    assert catch_record, "expected the server to receive the queued catch via the drain trigger"
    assert_equal @user.id, catch_record.user_id
    assert_equal 18, catch_record.length_inches.to_i
  end
end
