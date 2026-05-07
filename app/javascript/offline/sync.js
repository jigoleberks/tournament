import { pendingCatches, markSynced, markFailed } from "offline/db"

const ENDPOINT = "/api/catches"

let draining = false

async function drain() {
  // drain() is triggered from many sources (online, load, post-submit, SW message);
  // without this guard, two concurrent runs can pull the same pending row and POST
  // it twice, racing the server's client_uuid dedup.
  if (draining) return
  draining = true
  try {
    const pending = await pendingCatches()
    for (const rec of pending) {
      try {
        const fd = new FormData()
        fd.append("catch[client_uuid]", rec.client_uuid)
        fd.append("catch[species_id]", rec.species_id)
        fd.append("catch[length_inches]", rec.length_inches)
        fd.append("catch[captured_at_device]", rec.captured_at_device)
        if (rec.captured_at_gps) fd.append("catch[captured_at_gps]", rec.captured_at_gps)
        if (rec.latitude != null) fd.append("catch[latitude]", rec.latitude)
        if (rec.longitude != null) fd.append("catch[longitude]", rec.longitude)
        if (rec.gps_accuracy_m != null) fd.append("catch[gps_accuracy_m]", rec.gps_accuracy_m)
        if (rec.app_build) fd.append("catch[app_build]", rec.app_build)
        if (rec.note) fd.append("catch[note]", rec.note)
        if (rec.photo) fd.append("catch[photo]", rec.photo, "photo.jpg")
        if (rec.video) fd.append("catch[video]", rec.video, "video.webm")
        if (rec.teammate_user_id) fd.append("teammate_user_id", rec.teammate_user_id)

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
          // Session expired — leave queued so it retries after the user signs back in.
          // Marking failed here would hide the catch from the pending widget, and the
          // user would think it was lost.
        } else if (resp.status >= 400 && resp.status < 500 && resp.status !== 408 && resp.status !== 429) {
          const body = await resp.json().catch(() => ({}))
          await markFailed(rec.client_uuid, JSON.stringify(body))
          window.dispatchEvent(new CustomEvent("bsfamilies:catch-failed", { detail: { client_uuid: rec.client_uuid, reason: JSON.stringify(body) } }))
        }
      } catch (_) {
        // network error — leave queued for next attempt
      }
    }
  } finally {
    draining = false
  }
}

function csrfToken() {
  const el = document.querySelector("meta[name='csrf-token']")
  return el ? el.content : ""
}

window.addEventListener("online", () => { drain().catch(() => {}) })
window.addEventListener("bsfamilies:try-sync", () => { drain().catch(() => {}) })
window.addEventListener("load", () => { if (navigator.onLine) drain().catch(() => {}) })

navigator.serviceWorker?.addEventListener("message", (e) => {
  if (e.data?.type === "drain") drain().catch(() => {})
})
