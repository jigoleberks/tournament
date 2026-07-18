import { pendingCatches, markSynced, markFailed, pruneSynced, deferRetry } from "offline/db"
import { materialize } from "offline/blob"

const ENDPOINT = "/api/catches"
const SESSION_ENDPOINT = "/api/session"
const MAX_VIDEO_BYTES = 100 * 1024 * 1024  // keep in sync with Catch::VIDEO_MAX_BYTES

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

  // Preflight: one cheap GET before any photo body. It answers auth (a 401
  // here replaces N full-photo-upload 401s), returns a FRESH CSRF token (the
  // precached /offline shell renders no csrf meta at all — before this, every
  // shell-originated drain uploaded catch #1's photo just to 401 against
  // null_session — and bfcache restores can hold stale tokens), and tells us
  // who is signed in so we never drain another user's records.
  let session
  try {
    const resp = await fetch(SESSION_ENDPOINT, {
      headers: { "Accept": "application/json" }, credentials: "same-origin"
    })
    if (resp.status === 401) {
      window.dispatchEvent(new CustomEvent("bsfamilies:sync-auth-required"))
      return true
    }
    if (!resp.ok) return false
    session = await resp.json()
  } catch (_) {
    return false // network flake — next trigger retries, nothing uploaded
  }

  for (const rec of due) {
    // Queued under a different signed-in user (shared phone): leave it for
    // them. Records predating the stamp (no queued_by_user_id) drain as before.
    if (rec.queued_by_user_id && String(rec.queued_by_user_id) !== String(session.user_id)) continue
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
      // An unreadable or oversized video must not strand the catch — the photo
      // is the required part. Oversized would bounce off the server's cap (or a
      // proxy 413) and mark the whole catch failed, so drop it client-side.
      const videoOk = rec.video && (rec.video.size == null || rec.video.size <= MAX_VIDEO_BYTES)
      const video = videoOk ? await materialize(rec.video) : null

      const fd = new FormData()
      fd.append("catch[client_uuid]", rec.client_uuid)
      fd.append("catch[species_id]", rec.species_id)
      fd.append("catch[length_inches]", rec.length_inches)
      if (rec.length_unit) fd.append("catch[length_unit]", rec.length_unit)
      fd.append("catch[captured_at_device]", rec.captured_at_device)
      if (rec.captured_at_gps) fd.append("catch[captured_at_gps]", rec.captured_at_gps)
      if (rec.latitude != null) fd.append("catch[latitude]", rec.latitude)
      if (rec.longitude != null) fd.append("catch[longitude]", rec.longitude)
      if (rec.gps_accuracy_m != null) fd.append("catch[gps_accuracy_m]", rec.gps_accuracy_m)
      if (rec.app_build) fd.append("catch[app_build]", rec.app_build)
      if (rec.note) fd.append("catch[note]", rec.note)
      if (rec.tag_number) fd.append("catch[tag_number]", rec.tag_number)
      if (rec.weight_text) fd.append("catch[weight_text]", rec.weight_text)
      if (rec.queued_by_user_id) fd.append("catch[queued_by_user_id]", rec.queued_by_user_id)
      if (rec.video_failed) fd.append("catch[video_failed]", "true")
      fd.append("catch[photo]", photo, rec.photo.name || "photo.jpg")
      if (video) {
        const ext = (video.type || "").includes("mp4") ? "mp4" : "webm"
        fd.append("catch[video]", video, `video.${ext}`)
      }
      if (rec.teammate_user_id) fd.append("teammate_user_id", rec.teammate_user_id)

      const resp = await fetch(ENDPOINT, {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": session.csrf_token },
        body: fd,
        credentials: "same-origin"
      })
      if (resp.ok) {
        await markSynced(rec.client_uuid)
        window.dispatchEvent(new CustomEvent("bsfamilies:catch-synced", { detail: { client_uuid: rec.client_uuid } }))
      } else if (resp.status === 401) {
        // Session died between preflight and POST. Leave queued; stop the pass.
        window.dispatchEvent(new CustomEvent("bsfamilies:sync-auth-required"))
        return true
      } else if (resp.status >= 400 && resp.status < 500 && resp.status !== 408 && resp.status !== 429) {
        // A non-JSON body (reverse-proxy 413 for an oversized photo, etc.)
        // must still produce a readable reason — never raw JSON or "{}".
        const body = await resp.json().catch(() => null)
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
window.addEventListener("load", () => { if (navigator.onLine) drain().catch(() => {}) })

// iOS has no Background Sync, so foregrounding the app is our main retry trigger
// for catches queued during the event. Without this, pendings can sit until the
// user manually reopens the page (see 2026-05-13 wrong-winner incident).
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && navigator.onLine) drain().catch(() => {})
})

// iOS back-navigation restores pages from the bfcache without firing load;
// pageshow with persisted=true is the only signal those restores emit.
window.addEventListener("pageshow", (e) => {
  if (e.persisted && navigator.onLine) drain().catch(() => {})
})

// Turbo Drive visits don't fire load either — retry as the user browses in-app.
document.addEventListener("turbo:load", () => {
  if (navigator.onLine) drain().catch(() => {})
})

// Safety net for the no-lifecycle-event case (angler parked on the leaderboard
// with the app foregrounded): a slow tick retries while anything is queued.
// drain() exits after one cheap IndexedDB index read when the queue is empty.
// window.__syncRetryMs is a test override; real clients always use 45s.
const RETRY_MS = Number(window.__syncRetryMs) || 45000
setInterval(() => {
  if (navigator.onLine && document.visibilityState === "visible") drain().catch(() => {})
}, RETRY_MS)

navigator.serviceWorker?.addEventListener("message", (e) => {
  if (e.data?.type === "drain") drain().catch(() => {})
})
