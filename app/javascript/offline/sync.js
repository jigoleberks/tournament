import { pendingCatches, markSynced, markFailed, pruneSynced } from "offline/db"
import { materialize } from "offline/blob"

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

// One pass over the queue. Returns true to halt re-runs (auth is dead — every
// further attempt would upload a full photo body just to get another 401).
async function drainOnce() {
  await pruneSynced().catch(() => {})
  const pending = await pendingCatches()
  for (const rec of pending) {
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
      // An unreadable video must not strand the catch — the photo is the
      // required part and video is Phase-2-unused. Send without it.
      const video = rec.video ? await materialize(rec.video) : null

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
      fd.append("catch[photo]", photo, rec.photo.name || "photo.jpg")
      if (video) {
        const ext = (video.type || "").includes("mp4") ? "mp4" : "webm"
        fd.append("catch[video]", video, `video.${ext}`)
      }
      if (rec.teammate_user_id) fd.append("teammate_user_id", rec.teammate_user_id)
      if (rec.video_failed) fd.append("catch[video_failed]", "true")

      const resp = await fetch(ENDPOINT, {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": csrfToken() },
        body: fd,
        credentials: "same-origin"
      })
      if (resp.ok) {
        await markSynced(rec.client_uuid)
        window.dispatchEvent(new CustomEvent("bsfamilies:catch-synced", { detail: { client_uuid: rec.client_uuid } }))
      } else if (resp.status === 401) {
        // Session expired (or CSRF failure — null_session makes them look the
        // same). Leave queued so it retries after the user signs back in;
        // marking failed would hide the catch from the pending widget. But
        // don't be silent about it — that's how the 2026-05-13 wrong-winner
        // incident happened. Tell the page, and stop: every remaining record
        // would 401 the same way, each uploading its full photo body first.
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
      }
    } catch (_) {
      // network error — leave queued for next attempt
    }
  }
  return false
}

function csrfToken() {
  const el = document.querySelector("meta[name='csrf-token']")
  return el ? el.content : ""
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
