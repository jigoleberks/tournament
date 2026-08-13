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

  # When /api/session breaks with a non-401 (misrouted route, proxy 503 on
  # that path only), sync.js falls back to the page's meta token and can no
  # longer verify who is signed in — so another member's queued catch gets
  # uploaded and the server refuses it with queued_by_mismatch. That record
  # must stay PENDING (drains only pull pending rows; the right member's next
  # sign-in syncs it), never failed behind their back.
  test "a wrong-account catch stays pending when the preflight fallback uploads it" do
    other = create(:user)
    uuid = SecureRandom.uuid
    sign_in_as(@user)
    page.execute_script <<~JS
      // Forgery protection is off in the test env, so csrf_meta_tags renders
      // no meta — but the preflight-unavailable fallback only proceeds when
      // the page has one (offline-shell pages must keep waiting). Inject the
      // meta a production page would have; its value is never validated here.
      if (!document.querySelector("meta[name='csrf-token']")) {
        document.head.insertAdjacentHTML("beforeend", '<meta name="csrf-token" content="test-token">');
      }
      const realFetch = window.fetch;
      window.fetch = (url, opts) => {
        if (String(url).includes("/api/session")) {
          return Promise.resolve(new Response("busy", { status: 503 }));
        }
        return realFetch(url, opts);
      };
    JS
    seed_idb_catch(uuid: uuid, species_id: @walleye.id, queued_by_user_id: other.id,
                   trigger_js: "window.dispatchEvent(new Event('bsfamilies:try-sync'))")

    # deferRetry stamps next_attempt_at after the 422 round-trip — wait on that
    # rather than sleeping, then assert the record was left pending.
    Timeout.timeout(10) do
      sleep 0.1 until idb_next_attempt_at(uuid)
    end
    assert_equal "pending", idb_status_of(uuid)
    assert_no_selector "[data-pending-catches-target='failedList'] li"
    assert_nil Catch.find_by(client_uuid: uuid)
  end

  # A real server 422 (Walleye's length cap is 50″ — MAX_LENGTH_BY_SPECIES in
  # app/models/catch.rb) used to be shown to the angler as the raw response
  # body: {"errors":["Length inches for Walleye can't exceed 50\""]}. sync.js
  # must extract body.errors and join it into readable text before it ever
  # reaches markFailed / the bsfamilies:catch-failed detail.
  # A server-wide blip (redeploy, reverse-proxy 502) backs every queued catch
  # off, and deferRetry escalates to a 15-minute floor. The server is usually
  # healthy again within a minute, but nothing shortens the wait: drainOnce
  # filters pending rows on next_attempt_at, and the widget's Retry button is
  # rendered only for FAILED records — so an angler's fish sat off the
  # leaderboard for up to a quarter of an hour with the queue looking healthy.
  # One successful upload proves the server is reachable, so it must release
  # the rest of the queue.
  test "a successful upload releases catches parked in backoff" do
    parked = SecureRandom.uuid
    fresh = SecureRandom.uuid
    sign_in_as(@user)
    # Staged mid-outage: five failed attempts, still ~15 minutes to wait.
    seed_idb_catch(uuid: parked, species_id: @walleye.id, trigger_js: "void 0",
                   extra_fields: { next_attempt_at: "Date.now() + 900000", attempts: 5 })
    seed_idb_catch(uuid: fresh, species_id: @walleye.id,
                   trigger_js: "window.dispatchEvent(new Event('bsfamilies:try-sync'))")

    assert_catch_received(fresh)
    # Without the release this stays queued behind its 15-minute timer.
    assert_catch_received(parked)
  end

  # The release above is capped, because "the server is healthy" says nothing
  # about a record the server rejects every single time. Uncapped, an angler who
  # lands twenty good fish in an evening hands the broken one twenty releases —
  # and so twenty full-photo re-uploads over lake cellular, which is the exact
  # battery/data drain deferRetry exists to prevent. A record already released
  # its budget's worth (clearBackoff's MAX_RELEASES) serves out its backoff.
  test "a record that keeps failing stops being released by later successes" do
    control = SecureRandom.uuid
    spent = SecureRandom.uuid
    fresh = SecureRandom.uuid
    sign_in_as(@user)
    # Both parked; both also held (hold_until) so they stay put in IndexedDB for
    # inspection instead of racing an upload the moment they are released. The
    # only difference is the release budget: the control has spent none, `spent`
    # has spent all of clearBackoff's MAX_RELEASES.
    held = { hold_until: "Date.now() + 600000", next_attempt_at: "Date.now() + 900000", attempts: 5 }
    seed_idb_catch(uuid: control, species_id: @walleye.id, trigger_js: "void 0",
                   extra_fields: held)
    seed_idb_catch(uuid: spent, species_id: @walleye.id, trigger_js: "void 0",
                   extra_fields: held.merge(releases: 2))
    seed_idb_catch(uuid: fresh, species_id: @walleye.id,
                   trigger_js: "window.dispatchEvent(new Event('bsfamilies:try-sync'))")

    assert_catch_received(fresh)
    # The control losing its timer is clearBackoff reporting for duty — wait on
    # that rather than a sleep, so the assertion below can't run too early.
    Timeout.timeout(10) do
      sleep 0.1 while idb_next_attempt_at(control)
    end
    assert idb_next_attempt_at(spent),
           "a record that already spent its release budget must serve out its backoff"
  end

  # The budget above only makes sense if a release is charged when it actually
  # buys something. A parked row whose timer has ALREADY lapsed is due — its
  # retry happens with or without clearBackoff — so charging it a release burns
  # budget for nothing. Two such no-op charges exhaust MAX_RELEASES, and the
  # next real outage's recovery then skips the row: the one fish on the phone
  # that serves out its full backoff while the rest of the queue syncs.
  test "a parked record whose timer already lapsed is not charged a release" do
    lapsed = SecureRandom.uuid
    control = SecureRandom.uuid
    fresh = SecureRandom.uuid
    sign_in_as(@user)
    # Both parked and held (hold_until) so they stay inspectable in IndexedDB
    # instead of uploading the moment they are due. The only difference is the
    # timer: the control's is still running, `lapsed`'s has already expired.
    held = { hold_until: "Date.now() + 600000", attempts: 5 }
    seed_idb_catch(uuid: lapsed, species_id: @walleye.id, trigger_js: "void 0",
                   extra_fields: held.merge(next_attempt_at: "Date.now() - 1000"))
    seed_idb_catch(uuid: control, species_id: @walleye.id, trigger_js: "void 0",
                   extra_fields: held.merge(next_attempt_at: "Date.now() + 900000"))
    seed_idb_catch(uuid: fresh, species_id: @walleye.id,
                   trigger_js: "window.dispatchEvent(new Event('bsfamilies:try-sync'))")

    assert_catch_received(fresh)
    # The control losing its timer is clearBackoff reporting for duty — wait on
    # that rather than a sleep, so the assertion below can't run too early.
    Timeout.timeout(10) do
      sleep 0.1 while idb_next_attempt_at(control)
    end
    assert idb_next_attempt_at(lapsed),
           "an already-due record must be left alone (its stale timer intact), not released"
  end

  # offline/db.js bumps its schema version as the queue format changes, and an
  # upgrade cannot run while another same-origin context holds the old version
  # open — openDB's promise does not reject there, it hangs forever. Every
  # export in db.js awaits getDB(), so a page without a `blocking` handler
  # silently wedges the next deploy's submit(): the Save button stays disabled
  # and the fish is never written to the queue. Standing aside is what keeps
  # that from happening.
  test "a page holding the offline DB open stands aside for a newer schema" do
    sign_in_as(@user)
    page.execute_script <<~JS
      window.__newer = null;
      (async () => {
        const db = await import("offline/db");
        await db.getDB();                     // this page now holds the connection
        const req = indexedDB.open("bsfamilies", 99);
        req.onupgradeneeded = () => {};
        req.onsuccess = (e) => {
          // Leave the origin as we found it for the next test.
          e.target.result.close();
          indexedDB.deleteDatabase("bsfamilies");
          window.__newer = "open";
        };
        req.onerror = () => { window.__newer = "error" };
      })().catch((e) => { window.__newer = "error: " + e });
    JS

    # Without blocking() this poll times out — the upgrade never gets its turn.
    Timeout.timeout(10) do
      sleep 0.1 until page.evaluate_script("window.__newer")
    end
    assert_equal "open", page.evaluate_script("window.__newer")
  end

  # Every drain trigger (the 45s tick, turbo:load, visibilitychange, pageshow,
  # online) and every pending-widget render scans the queue with
  # getAllFromIndex, which deserializes whole records. Once photos became inline
  # ArrayBuffers rather than out-of-line Blobs, that meant materializing every
  # queued photo into the JS heap just to read next_attempt_at and hold_until.
  # offline/db.js v2 keeps the bytes in a separate store; only getCatch — called
  # once, immediately before an upload — joins them back.
  test "a queued catch keeps its bytes out of the row the queue scan reads" do
    sign_in_as(@user)
    page.execute_script <<~JS
      window.__probe = null;
      (async () => {
        const db = await import("offline/db");
        await db.enqueueCatch({
          client_uuid: "#{SecureRandom.uuid}",
          species_id: "#{@walleye.id}",
          length_inches: "18",
          captured_at_device: new Date().toISOString(),
          photo: { bytes: new ArrayBuffer(2048), type: "image/jpeg", name: "p.jpg" }
        });
        const [row] = await db.pendingCatches();
        const full = await db.getCatch(row.client_uuid);
        window.__probe = {
          scanned_row_has_photo: row.photo !== undefined,
          scanned_row_has_length: row.length_inches === "18",
          joined_read_has_photo: !!(full.photo && full.photo.bytes && full.photo.bytes.byteLength === 2048)
        };
      })().catch((e) => { window.__probe = { error: String(e) }; });
    JS

    probe = nil
    Timeout.timeout(10) do
      sleep 0.1 until (probe = page.evaluate_script("window.__probe"))
    end
    assert_nil probe["error"], "enqueue/read probe errored: #{probe["error"]}"
    assert probe["scanned_row_has_length"], "the queue scan must still see the scheduling metadata"
    refute probe["scanned_row_has_photo"], "the queue scan must not deserialize the photo bytes"
    assert probe["joined_read_has_photo"], "getCatch must still hand the uploader its bytes"
  end

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

  # WebKit can report navigator.onLine === false on a device that is actually
  # online (stale flag after backgrounding, standalone PWAs). The flag must be
  # a hint at most — a drain trigger firing while onLine is wrongly false must
  # still attempt the upload (the preflight fetch handles the truly-offline
  # case by failing silently).
  test "pending catch uploads even when navigator.onLine reports false" do
    uuid = SecureRandom.uuid
    apply_ios_shims(extra_js: 'Object.defineProperty(navigator, "onLine", { configurable: true, get: () => false });')
    sign_in_as(@user)
    seed_idb_catch(uuid: uuid, species_id: @walleye.id,
                   trigger_js: "document.dispatchEvent(new Event('visibilitychange'))")
    assert_catch_received(uuid)
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
