import { pendingCatches, getCatch, markSynced, markFailed, pruneSynced, deferRetry, clearBackoff } from "offline/db"
import { materialize } from "offline/blob"
import { buildCatchFormData } from "offline/form_data"
import { fetchSession } from "offline/session"

const ENDPOINT = "/api/catches"

let draining = false
let rerunRequested = false

async function drain() {
  // drain() is triggered from many sources (online, load, turbo:load, post-submit,
  // SW message); without this guard, two concurrent runs can pull the same pending
  // row and POST it twice, racing the server's client_uuid dedup. A trigger that
  // lands mid-drain must NOT be dropped though — a Retry tap during a slow drain
  // would silently do nothing — so it queues one re-run instead.
  if (draining) { rerunRequested = true; return }
  draining = true
  try {
    do {
      rerunRequested = false
      const halted = await drainOnce()
      if (halted) break
    } while (rerunRequested)
  } finally {
    draining = false
    rerunRequested = false
  }
}

// One pass over the queue. Returns true to halt re-runs (auth is dead).
async function drainOnce() {
  await pruneSynced().catch(() => {})
  const pending = await pendingCatches()
  const now = Date.now()
  const due = pending.filter((rec) =>
    !(rec.next_attempt_at && rec.next_attempt_at > now) &&  // backing off after server errors
    !(rec.hold_until && rec.hold_until > now)               // submit() still acquiring GPS
  )
  if (due.length === 0) return false

  // Preflight (offline/session.js): a 401 here replaces N full-photo-upload
  // 401s, and knowing who is signed in means we never drain another user's
  // records.
  const preflight = await fetchSession()
  if (preflight.state === "authRequired") {
    window.dispatchEvent(new CustomEvent("bsfamilies:sync-auth-required"))
    return true
  }
  if (preflight.state === "network") {
    return false // network flake — next trigger retries, nothing uploaded
  }
  let session
  if (preflight.state === "ok") {
    session = preflight
  } else {
    // Preflight endpoint broken (misrouted /api/session, maintenance rule)
    // while POST /api/catches may still work — fall back to the page's meta
    // token rather than stranding the queue with no signal, the same
    // fallback the manual recover flow keeps. The precached /offline shell
    // renders no csrf meta, so from the shell we still wait for the next
    // trigger. user_id: null skips the client-side other-user check below;
    // the server's queued_by guard answers those uploads with its
    // queued_by_mismatch 422, which the loop below leaves PENDING (with
    // backoff) for the right member — never marked failed behind their back.
    const meta = document.querySelector("meta[name='csrf-token']")
    if (!meta || !meta.content) return false
    session = { csrf_token: meta.content, user_id: null }
  }

  for (const snap of due) {
    // Re-read the row before uploading: the queue snapshot above predates the
    // preflight round-trip, and a page resumed from iOS suspension re-arms
    // hold_until (and writes late GPS coords) in exactly that window — see
    // catch_form submit(). The re-read costs one IndexedDB get and makes the
    // freshest hold/coords the ones that upload.
    const rec = await getCatch(snap.client_uuid)
    if (!rec || rec.status !== "pending") continue
    if (rec.hold_until && rec.hold_until > Date.now()) continue
    // Queued under a different signed-in user (shared phone): leave it for
    // them. Records predating the stamp (no queued_by_user_id) drain as before.
    if (rec.queued_by_user_id && session.user_id != null && String(rec.queued_by_user_id) !== String(session.user_id)) continue
    try {
      // Materialize BEFORE building the body. New records carry inline bytes;
      // legacy records carry a file-backed IndexedDB blob that can make WebKit
      // send an empty-bodied request instead of throwing, so we prove we can
      // read the bytes first and never POST if we can't.
      const photo = await materialize(rec.photo)
      if (!photo) {
        const reason = "Photo could not be read from this device"
        await markFailed(rec.client_uuid, reason)
        window.dispatchEvent(new CustomEvent("bsfamilies:catch-failed", { detail: { client_uuid: rec.client_uuid, reason } }))
        continue
      }
      const fd = await buildCatchFormData(rec, photo, rec.photo.name || "photo.jpg")

      const resp = await fetch(ENDPOINT, {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": session.csrf_token },
        body: fd,
        credentials: "same-origin"
      })
      if (resp.ok) {
        await markSynced(rec.client_uuid)
        // This upload proves the server is healthy, so release anything still
        // sitting out a backoff from an earlier outage and queue another pass
        // to carry it — otherwise it waits out a timer we now know is stale.
        if (await clearBackoff()) rerunRequested = true
        window.dispatchEvent(new CustomEvent("bsfamilies:catch-synced", { detail: { client_uuid: rec.client_uuid } }))
      } else if (resp.status === 401) {
        // Session died between preflight and POST. Leave queued; stop the pass.
        window.dispatchEvent(new CustomEvent("bsfamilies:sync-auth-required"))
        return true
      } else if (resp.status >= 400 && resp.status < 500 && resp.status !== 408 && resp.status !== 429) {
        // A non-JSON body (reverse-proxy 413 for an oversized photo, etc.)
        // must still produce a readable reason — never raw JSON or "{}".
        const body = await resp.json().catch(() => null)
        if (body && body.code === "queued_by_mismatch") {
          // Only reachable when the preflight fallback uploaded with an
          // unverifiable user (user_id: null above): the record belongs to
          // another member of a shared phone. Failing it would strand it —
          // drains only pull pending records, so it would never auto-sync
          // when the right member signs back in. Leave it pending; back off
          // so we don't re-upload the full photo every 45s meanwhile.
          await deferRetry(rec.client_uuid)
          continue
        }
        const reason = body && Array.isArray(body.errors) && body.errors.length
          ? body.errors.join(", ")
          : `Upload failed (server error ${resp.status})`
        await markFailed(rec.client_uuid, reason)
        window.dispatchEvent(new CustomEvent("bsfamilies:catch-failed", { detail: { client_uuid: rec.client_uuid, reason } }))
      } else {
        // 5xx / 408 / 429: server reachable but unhappy — back off so we don't
        // re-upload this record's full photo body every 45 seconds for hours.
        await deferRetry(rec.client_uuid)
      }
    } catch (_) {
      // network error — leave queued for next attempt (no backoff: when the
      // signal comes back on the water, sync should happen immediately)
    }
  }
  return false
}

window.addEventListener("online", () => { drain().catch(() => {}) })
window.addEventListener("bsfamilies:try-sync", () => { drain().catch(() => {}) })
window.addEventListener("load", () => { drain().catch(() => {}) })

// iOS has no Background Sync, so foregrounding the app is our main retry trigger
// for catches queued during the event. Without this, pendings can sit until the
// user manually reopens the page (see 2026-05-13 wrong-winner incident).
// NOTE: no navigator.onLine gate on any trigger — WebKit's flag goes stale
// (false while actually online) after backgrounding, and a wrongly-false flag
// here stranded queued catches on phones with working connectivity. The
// preflight fetch in drainOnce() is the real reachability check; when truly
// offline it fails silently and the next trigger retries.
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") drain().catch(() => {})
})

// iOS back-navigation restores pages from the bfcache without firing load;
// pageshow with persisted=true is the only signal those restores emit.
window.addEventListener("pageshow", (e) => {
  if (e.persisted) drain().catch(() => {})
})

// Turbo Drive visits don't fire load either — retry as the user browses in-app.
document.addEventListener("turbo:load", () => {
  drain().catch(() => {})
})

// Safety net for the no-lifecycle-event case (angler parked on the leaderboard
// with the app foregrounded): a slow tick retries while anything is queued.
// drain() exits after one cheap IndexedDB index read when the queue is empty.
// window.__syncRetryMs is a test override; real clients always use 45s.
const RETRY_MS = Number(window.__syncRetryMs) || 45000
setInterval(() => {
  if (document.visibilityState === "visible") drain().catch(() => {})
}, RETRY_MS)

navigator.serviceWorker?.addEventListener("message", (e) => {
  if (e.data?.type === "drain") drain().catch(() => {})
})
