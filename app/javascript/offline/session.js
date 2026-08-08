// The one spelling of the /api/session auth+CSRF preflight, shared by the
// background drain (offline/sync.js) and the manual recovery tool
// (recover_controller.js). One cheap GET before any photo body: it answers
// auth without burning a full upload on a 401, returns a FRESH CSRF token
// (the precached /offline shell renders no csrf meta at all, and iOS bfcache
// restores can hold stale ones), and says who is signed in. The service
// worker's pushsubscriptionchange handler keeps its own inline copy — a
// classic SW script can't import importmap modules.
//
// Callers keep their own policy for each state:
//   { state: "ok", csrf_token, user_id }  — fresh session
//   { state: "authRequired" }             — 401: signed out
//   { state: "unavailable" }              — endpoint broken (misrouted,
//                                           maintenance rule); POSTs may
//                                           still work with the meta token
//   { state: "network" }                  — fetch threw: offline / flake
export async function fetchSession() {
  let resp
  try {
    resp = await fetch("/api/session", {
      headers: { "Accept": "application/json" }, credentials: "same-origin"
    })
  } catch (_) {
    return { state: "network" }
  }
  if (resp.status === 401) return { state: "authRequired" }
  if (!resp.ok) return { state: "unavailable" }
  try {
    const data = await resp.json()
    return { state: "ok", csrf_token: data.csrf_token, user_id: data.user_id }
  } catch (_) {
    return { state: "network" } // truncated mid-body — same as a flake
  }
}
