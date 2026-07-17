require "application_system_test_case"

# Locks in the iOS-friendly drain triggers and failure handling in
# app/javascript/offline/sync.js. A queued catch in IndexedDB must upload when:
#   - visibilitychange fires with the document visible (foregrounding the PWA)
#   - bsfamilies:try-sync fires (manual retry from the pending-catches widget)
#   - pageshow fires with persisted=true (iOS bfcache back-navigation restore)
#   - turbo:load fires (in-app Turbo navigation)
#   - the slow retry interval ticks (no lifecycle event at all)
#
# Background: on 2026-05-13 a tournament called the wrong winner because an
# iOS Safari catch sat stuck-pending until the angler went home and reopened
# his phone — iOS has no Background Sync API, so the page must be alive to
# drain. Losing any of these triggers re-opens that incident.
#
# Shared IndexedDB seeding/inspection and iOS shims: test/support/ios_web_quirks.rb.
class OfflineSyncTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Joe")
    @walleye = create(:species, club: @club, name: "Walleye")
  end

  test "pending IndexedDB catch uploads when visibilitychange fires" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    seed_idb_catch(uuid: uuid, species_id: @walleye.id,
                   trigger_js: "document.dispatchEvent(new Event('visibilitychange'))")
    assert_catch_received(uuid)
  end

  test "pending IndexedDB catch uploads when bsfamilies:try-sync fires" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    seed_idb_catch(uuid: uuid, species_id: @walleye.id,
                   trigger_js: "window.dispatchEvent(new Event('bsfamilies:try-sync'))")
    assert_catch_received(uuid)
  end

  # iOS back-navigation restores pages from the bfcache WITHOUT firing load —
  # the drain trigger that covers normal arrivals. pageshow with persisted=true
  # is the only signal those restores emit.
  test "pending catch uploads when a bfcache restore fires pageshow" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    seed_idb_catch(uuid: uuid, species_id: @walleye.id,
                   trigger_js: "window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }))")
    assert_catch_received(uuid)
  end

  # Turbo Drive visits never fire load either — an angler who keeps browsing
  # in-app after signal returns should not need to background the app to sync.
  test "pending catch uploads on the next turbo:load navigation" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    seed_idb_catch(uuid: uuid, species_id: @walleye.id,
                   trigger_js: "document.dispatchEvent(new Event('turbo:load'))")
    assert_catch_received(uuid)
  end

  # Safety net: if no lifecycle event ever fires (user sits on one screen with
  # the app foregrounded, e.g. watching the leaderboard), a slow retry tick
  # must eventually drain the queue. The tick period is overridable via
  # window.__syncRetryMs so the test doesn't wait 45 real seconds.
  test "pending catch uploads via the retry interval with no user action" do
    uuid = SecureRandom.uuid
    apply_ios_shims(sync_retry_ms: 300)
    sign_in_as(@user)
    seed_idb_catch(uuid: uuid, species_id: @walleye.id, trigger_js: "void 0")
    assert_catch_received(uuid)
  end

  # Safari evicts ALL script-writable storage (IndexedDB included) after ~7
  # days without interaction unless the origin holds persistent storage. A
  # queued catch must survive that window, so the first enqueue on a page
  # requests persistence. Once per page is enough — repeat calls are no-ops.
  test "enqueueCatch requests persistent storage once" do
    sign_in_as(@user)
    page.execute_script <<~JS
      window.__persistCalls = 0;
      navigator.storage.persist = () => { window.__persistCalls++; return Promise.resolve(true); };
      window.__enqueued = false;
      (async () => {
        const { enqueueCatch } = await import("offline/db");
        const rec = (uuid) => ({
          client_uuid: uuid, species_id: "1", length_inches: "18",
          captured_at_device: new Date().toISOString(),
          photo: { bytes: new Uint8Array([1]).buffer, type: "image/jpeg", name: "p.jpg", size: 1 }
        });
        await enqueueCatch(rec("#{SecureRandom.uuid}"));
        await enqueueCatch(rec("#{SecureRandom.uuid}"));
        window.__enqueued = true;
      })().catch((err) => { window.__enqueueError = String(err); });
    JS

    Timeout.timeout(5) do
      loop do
        break if page.evaluate_script("window.__enqueued === true")
        err = page.evaluate_script("window.__enqueueError || null")
        flunk "enqueue errored: #{err}" if err
        sleep 0.05
      end
    end
    assert_equal 1, page.evaluate_script("window.__persistCalls"),
                 "expected exactly one navigator.storage.persist() call across two enqueues"
  end

  # A drain that hits 401 (expired session — or a CSRF failure, which
  # null_session makes indistinguishable) correctly leaves catches queued, but
  # used to do so in total silence: the exact silent-stranding shape of the
  # 2026-05-13 wrong-winner incident. The angler must be told to sign in.
  test "a 401 drain shows the sign-in-to-sync notice and keeps the catch queued" do
    uuid = SecureRandom.uuid
    visit "/session/new"
    seed_idb_catch(uuid: uuid, species_id: @walleye.id,
                   trigger_js: "window.dispatchEvent(new Event('bsfamilies:try-sync'))")

    assert_selector "[data-controller='sync-auth-notice']:not([hidden])", wait: 5
    assert_text(/sign in/i)
    assert_text(/catch/i)
    assert_nil Catch.find_by(client_uuid: uuid)

    # Still queued — signing back in must be able to resume it.
    assert_equal "pending", idb_status_of(uuid)
  end

  test "a catch whose photo cannot be read is failed on-device and never POSTed" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    seed_idb_catch(uuid: uuid, species_id: @walleye.id,
                   photo_js: IosWebQuirks::UNREADABLE_PHOTO_JS, trigger_js: "void 0")
    page.execute_script("window.dispatchEvent(new Event('bsfamilies:try-sync'))")

    # sync.js marks it failed and fires bsfamilies:catch-failed, which the
    # pending-catches widget listens for and re-renders.
    # NOTE: the failure *reason* is asserted below, not here — this test is
    # about the on-device photo-unreadable branch, not the server 4xx branch.
    assert_selector "[data-pending-catches-target='failedList'] li", wait: 5
    assert_nil Catch.find_by(client_uuid: uuid),
               "sync.js must not POST a catch whose photo can't be read"
  end

  # A real server 422 (Walleye's length cap is 50″ — MAX_LENGTH_BY_SPECIES in
  # app/models/catch.rb) used to be shown to the angler as the raw response
  # body: {"errors":["Length inches for Walleye can't exceed 50\""]}. sync.js
  # must extract body.errors and join it into readable text before it ever
  # reaches markFailed / the bsfamilies:catch-failed detail.
  test "a server 422 shows a readable reason, not raw JSON" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    seed_idb_catch(uuid: uuid, species_id: @walleye.id, length_inches: "60",
                   trigger_js: "window.dispatchEvent(new Event('bsfamilies:try-sync'))")

    assert_selector "[data-pending-catches-target='failedList'] li", wait: 5
    assert_text(/can't exceed/, wait: 5)
    assert_no_text('{"errors"')
    assert_no_text('"errors":')
    assert_nil Catch.find_by(client_uuid: uuid)
  end

  # A 4xx that doesn't come from the Rails API — a reverse-proxy 413 for an
  # oversized photo is the realistic case — has an HTML body. resp.json()
  # fails, and the old fallback rendered the reason as literally "{}". The
  # widget must show a readable message instead.
  test "a non-JSON 4xx shows a readable reason, not {}" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    page.execute_script <<~JS
      const realFetch = window.fetch;
      window.fetch = (url, opts) => {
        if (String(url).includes("/api/catches")) {
          return Promise.resolve(new Response("<html>413 Request Entity Too Large</html>",
            { status: 413, headers: { "Content-Type": "text/html" } }));
        }
        return realFetch(url, opts);
      };
    JS
    seed_idb_catch(uuid: uuid, species_id: @walleye.id,
                   trigger_js: "window.dispatchEvent(new Event('bsfamilies:try-sync'))")

    assert_selector "[data-pending-catches-target='failedList'] li", wait: 5
    assert_text(/upload failed \(server error 413\)/i, wait: 5)
    assert_no_text "{}"
    assert_nil Catch.find_by(client_uuid: uuid)
  end

  # Synced rows used to be kept forever with their full photo/video blobs —
  # unbounded IndexedDB growth is what invites iOS storage-pressure eviction,
  # and eviction takes genuinely-pending catches with it. Once the server owns
  # the catch, the local row must go.
  test "a successfully synced catch is deleted from IndexedDB" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    seed_idb_catch(uuid: uuid, species_id: @walleye.id,
                   trigger_js: "window.dispatchEvent(new Event('bsfamilies:try-sync'))")
    assert_catch_received(uuid)
    assert_idb_row_gone(uuid)
  end

  test "legacy synced rows are pruned when the queue drains" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    # Seed a row already in status "synced" (as the pre-fix code left behind),
    # then trigger a drain — it must be swept even though nothing new synced.
    seed_idb_catch(uuid: uuid, species_id: @walleye.id, status: "synced",
                   trigger_js: "window.dispatchEvent(new Event('bsfamilies:try-sync'))")
    assert_idb_row_gone(uuid)
    assert_nil Catch.find_by(client_uuid: uuid), "a legacy synced row must be pruned, not re-POSTed"
  end

  # New-format records store raw bytes (ArrayBuffer) instead of a Blob —
  # ArrayBuffers serialize INLINE in the IndexedDB record, sidestepping
  # WebKit's file-backed-blob bug entirely. sync.js must upload these.
  # (The Blob-photo tests above double as the legacy-record regression guard.)
  test "a bytes-format record (ArrayBuffer photo) uploads on drain" do
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    seed_idb_catch(uuid: uuid, species_id: @walleye.id,
                   photo_js: IosWebQuirks::BYTES_PHOTO_JS,
                   trigger_js: "window.dispatchEvent(new Event('bsfamilies:try-sync'))")
    assert_catch_received(uuid)
    assert_idb_row_gone(uuid)
  end

  private

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
