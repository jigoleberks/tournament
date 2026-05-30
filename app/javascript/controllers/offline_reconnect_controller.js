import { Controller } from "@hotwired/stimulus"

// On the cached /offline shell, a regained connection means we should leave the
// static shell for a real authenticated page. Reloading to "/" lets the normal
// page's offline/sync.js drain the queued catches with a valid session + CSRF
// token — the shell itself has neither and would 401 on upload.
//
// We must NOT redirect on navigator.onLine alone. `onLine` (and the "online"
// event) only report that a network interface is up, not that *our* server is
// reachable — wifi is up on a dead-zone phone, a captive portal, or while the
// host is restarting. If we redirect to "/" while the server is still
// unreachable, the service worker re-serves this very shell for that navigation
// and we redirect again: an infinite flash loop that locks the user out of the
// form. So we probe the origin for real and only leave on a confirmed response.
export default class extends Controller {
  connect() {
    this.boundCheck = () => this.check()
    window.addEventListener("online", this.boundCheck)
    // navigator.onLine === false means we're definitely offline — skip the probe
    // and stay. Otherwise verify the server actually answers before bailing out.
    if (navigator.onLine) this.check()
  }

  disconnect() {
    this._stopped = true
    window.removeEventListener("online", this.boundCheck)
  }

  async check() {
    if (this._leaving || this._checking || this._stopped) return
    this._checking = true
    let reachable = false
    try {
      // HEAD bypasses the service worker (it only handles GET), so this is a
      // truthful network probe: it resolves only if the origin actually replied.
      const res = await fetch("/", { method: "HEAD", cache: "no-store" })
      reachable = res.ok
    } catch {
      reachable = false
    }
    this._checking = false
    if (reachable && !this._leaving && !this._stopped) {
      this._leaving = true
      window.location.href = "/"
    }
  }
}
