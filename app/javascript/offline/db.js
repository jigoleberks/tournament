import { openDB } from "idb";

const DB_NAME = "bsfamilies";
const VERSION = 2;

// v2 splits the photo/video bytes out of the `catches` row into `blobs`.
// Every drain (45s tick, turbo:load, visibilitychange, pageshow, online) and
// every pending-widget render reads the queue with getAllFromIndex, which
// deserializes whole records — and since photos became inline ArrayBuffers
// rather than out-of-line Blobs, that meant materializing every queued photo
// into the JS heap just to read two scheduling timestamps. Metadata now lives
// alone; the bytes are fetched only by getCatch, right before an upload.
//
// The upgrade is purely additive: existing v1 rows keep their inline bytes and
// are still read (and uploaded) through the fallback in getCatch. Rewriting
// them would put the only copy of an unsynced fish's photo through a migration
// for no gain — the queue drains within hours and the fat rows go with it.
//
// A version bump cannot proceed while any other same-origin context still holds
// a connection on the old schema, and in that state openDB's promise never
// settles — it does not reject, it simply hangs. Every export here awaits
// getDB(), so an unguarded block hangs catch_form's submit() forever: the Save
// button stays disabled, its catch never runs, and the fish is never written to
// the queue. The `blocked`/`blocking` pair below is what keeps that from being
// a silent data-loss path on deploy day.
export const DB_BLOCKED_MESSAGE =
  "Another window of this app is open on an older version. Close the app's other tabs (or fully close and reopen it), then try again.";

// How long to let a blocking context get out of the way before failing. A page
// running a build that has the `blocking` handler below closes on the next tick;
// one running an older build never will, and an angler holding a fish should
// not wait on it.
const BLOCKED_GRACE_MS = 3000;

// One connection per page, not one per call. `blocking` needs a handle to close,
// and drains call in here several times a pass.
let dbPromise = null;

export async function getDB() {
  if (!dbPromise) dbPromise = open();
  return dbPromise;
}

function open() {
  let handle = null;
  let promise = null;
  let onBlocked;
  const blockedOut = new Promise((_, reject) => { onBlocked = reject; });

  const opening = openDB(DB_NAME, VERSION, {
    upgrade(db) {
      if (!db.objectStoreNames.contains("catches")) {
        const store = db.createObjectStore("catches", { keyPath: "client_uuid" });
        store.createIndex("status", "status");
      }
      if (!db.objectStoreNames.contains("blobs")) {
        db.createObjectStore("blobs", { keyPath: "client_uuid" });
      }
    },
    // Someone else is holding the old version open. Fail with something the
    // angler can act on rather than hanging — the open keeps running, so a
    // retry after they close the other window lands immediately.
    blocked() {
      setTimeout(() => {
        const err = new Error(DB_BLOCKED_MESSAGE);
        err.userMessage = DB_BLOCKED_MESSAGE;
        onBlocked(err);
      }, BLOCKED_GRACE_MS);
    },
    // The mirror image: a newer version wants to upgrade and we are the stale
    // connection in its way. Closing is what spares the NEXT schema bump the
    // failure above — this deploy's blocker is a build that predates this line.
    blocking(currentVersion, blockedVersion, event) {
      try { (handle || event?.target)?.close(); } catch (_) {}
      release(promise);
    },
    // Connection dropped from under us (storage pressure, forced close): drop
    // the cached handle so the next call reopens instead of reusing a dead one.
    terminated() {
      release(promise);
    }
  }).then((db) => { handle = db; return db; });

  promise = Promise.race([opening, blockedOut]);
  // Never cache a failed open, or one blocked moment poisons the page.
  promise.catch(() => release(promise));
  return promise;
}

function release(promise) {
  if (dbPromise === promise) dbPromise = null;
}

// Safari evicts all script-writable storage (this DB included) after ~7 days
// without site interaction unless the origin holds persistent storage. Ask
// once per page, on first enqueue — when we demonstrably have data worth
// keeping. Fire-and-forget: a denial changes nothing about how we proceed.
let persistRequested = false;

export async function enqueueCatch(record) {
  if (!persistRequested) {
    persistRequested = true;
    try { navigator.storage?.persist?.() } catch (_) {}
  }
  const db = await getDB();
  const { photo, video, ...meta } = record;
  // One transaction over both stores: a catch row whose bytes didn't land (or
  // bytes with no row) is a fish that can never upload, so they commit together.
  const tx = db.transaction(["catches", "blobs"], "readwrite");
  tx.objectStore("catches").put({ ...meta, status: "pending", queued_at: Date.now() });
  tx.objectStore("blobs").put({ client_uuid: record.client_uuid, photo, video });
  await tx.done;
}

// Metadata only for rows written by v2 — see the note on getDB. Callers that
// need the bytes (sync's upload, recover's preview) re-read with getCatch.
export async function pendingCatches() {
  const db = await getDB();
  return db.getAllFromIndex("catches", "status", "pending");
}

export async function getCatch(client_uuid) {
  const db = await getDB();
  const rec = await db.get("catches", client_uuid);
  if (!rec) return rec;
  // No blobs row means a v1 record still carrying its bytes inline.
  const bytes = await db.get("blobs", client_uuid);
  return bytes ? { ...rec, photo: bytes.photo, video: bytes.video } : rec;
}

export async function failedCatches() {
  const db = await getDB();
  return db.getAllFromIndex("catches", "status", "failed");
}

// Once the server confirms the catch, it owns the data — keeping the local row
// (with its full photo/video blobs) grows IndexedDB without bound, which is
// what invites iOS storage-pressure eviction. Eviction takes the whole DB,
// including catches still waiting to upload, so synced rows are deleted.
export async function markSynced(client_uuid) {
  const db = await getDB();
  const tx = db.transaction(["catches", "blobs"], "readwrite");
  tx.objectStore("catches").delete(client_uuid);
  tx.objectStore("blobs").delete(client_uuid);
  await tx.done;
}

// Sweep rows left in status "synced" by versions that kept them. One index
// read per drain; a no-op once legacy rows are gone.
export async function pruneSynced() {
  const db = await getDB();
  const stale = await db.getAllKeysFromIndex("catches", "status", "synced");
  if (stale.length === 0) return;
  const tx = db.transaction(["catches", "blobs"], "readwrite");
  for (const key of stale) {
    tx.objectStore("catches").delete(key);
    tx.objectStore("blobs").delete(key);
  }
  await tx.done;
}

export async function markFailed(client_uuid, reason) {
  const db = await getDB();
  const rec = await db.get("catches", client_uuid);
  if (rec) await db.put("catches", { ...rec, status: "failed", reason, failed_at: Date.now() });
}

export async function markPending(client_uuid) {
  const db = await getDB();
  const rec = await db.get("catches", client_uuid);
  // A hand-tapped Retry is a clean slate — including the clearBackoff release
  // budget, or a record retried by hand hours later would still be excluded.
  if (rec) await db.put("catches", { ...rec, status: "pending", reason: null, failed_at: null, attempts: 0, next_attempt_at: null, releases: 0 });
}

// Exponential backoff for records the server keeps 5xx/408/429-ing: without
// it, every 45s tick re-uploads the full multi-MB photo body of a
// deterministically failing record — a battery/data drain on the water.
// Network-level failures do NOT defer (signal returning should sync
// immediately); only "server reachable but erroring" does.
export async function deferRetry(client_uuid) {
  const db = await getDB();
  const rec = await db.get("catches", client_uuid);
  if (!rec || rec.status !== "pending") return;
  const attempts = (rec.attempts || 0) + 1;
  const delayMs = Math.min(45000 * 2 ** attempts, 15 * 60 * 1000);
  await db.put("catches", { ...rec, attempts, next_attempt_at: Date.now() + delayMs });
}

// A successful upload proves the server is reachable, so every other pending
// record should stop serving out a backoff that was set during the outage —
// otherwise a redeploy that lasted a minute keeps a caught fish off the
// leaderboard for up to the full 15-minute cap, with no way to hurry it (the
// widget's Retry button only exists for FAILED records). Returns how many rows
// were released so the caller can re-run the drain immediately.
//
// `attempts` is deliberately NOT reset: a record the server rejects
// deterministically gets one more try and then falls straight back to its long
// delay, instead of re-uploading its full photo body after every unrelated
// success — which is the battery/data drain deferRetry exists to prevent.
//
// That alone doesn't bound the cost, though: the delay stops growing but the
// releases don't stop coming. An angler who logs twenty good fish over an hour
// hands a record the server rejects EVERY time twenty releases, and so twenty
// full-photo re-uploads over lake cellular. `releases` caps them. A record
// released once and re-parked has now failed with the server demonstrably
// healthy — that is the signature of a broken record rather than an outage
// victim — so it gets one more chance and then serves out its backoff.
const MAX_RELEASES = 2;

export async function clearBackoff() {
  const db = await getDB();
  const rows = await db.getAllFromIndex("catches", "status", "pending");
  // Strictly future timers only: a row whose next_attempt_at already lapsed is
  // due — its retry happens with or without us — so "releasing" it buys nothing
  // and burning a release for it would spend MAX_RELEASES on no-ops.
  const parked = rows.filter((rec) => rec.next_attempt_at > Date.now() && (rec.releases || 0) < MAX_RELEASES);
  if (parked.length === 0) return 0;
  // One transaction for the whole release (same idiom as pruneSynced): a page
  // killed mid-release then frees all rows or none, never a half-applied mix.
  const tx = db.transaction("catches", "readwrite");
  for (const rec of parked) {
    tx.store.put({ ...rec, next_attempt_at: null, releases: (rec.releases || 0) + 1 });
  }
  await tx.done;
  return parked.length;
}

// submit() persists the catch BEFORE waiting up to ~10s for a GPS fix (the
// old order lost catch+photo entirely if iOS jetsammed the tab mid-geolocate
// — the normal lock-phone-and-release-the-fish gesture). hold_until keeps the
// coordless record out of drains while the fix is pending; it self-expires,
// so a killed page still syncs the catch (GPS-less, missing_gps-flagged).
export async function updateCoords(client_uuid, coords) {
  const db = await getDB();
  const rec = await db.get("catches", client_uuid);
  if (!rec) return;
  await db.put("catches", { ...rec, ...coords });
}

export async function releaseHold(client_uuid) {
  const db = await getDB();
  const rec = await db.get("catches", client_uuid);
  if (!rec || rec.hold_until == null) return;
  await db.put("catches", { ...rec, hold_until: null });
}

// Re-arm the hold when the page RESUMES from an iOS suspension mid-geolocate:
// the wall clock kept running while the pending getCurrentPosition was frozen,
// so the original hold can be expired the instant the page wakes — and the
// visibilitychange drain would upload the record coordless moments before the
// resumed fix lands. Only meaningful while the submitting page is alive; a
// killed page never re-arms, so the record still self-releases and syncs.
export async function extendHold(client_uuid, ms) {
  const db = await getDB();
  const rec = await db.get("catches", client_uuid);
  if (!rec || rec.status !== "pending") return;
  await db.put("catches", { ...rec, hold_until: Date.now() + ms });
}
