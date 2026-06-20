import { Controller } from "@hotwired/stimulus"

// Shown on the cached /offline shell. The user stays here logging catches into
// IndexedDB until they choose to return — we never auto-redirect. (A
// steady-but-slow connection would otherwise ping-pong them: redirect to "/",
// the SW times out at 3s, back to the shell, repeat.) Tapping "Back to live"
// navigates to "/", where the real authenticated page's offline/sync.js drains
// the queue with a valid CSRF token. A background HEAD probe only updates a
// status hint and has no navigation side-effect.
export default class extends Controller {
  static targets = ["status"]

  connect() {
    this.boundProbe = () => this.probe()
    this.boundOffline = () => this.markOffline()
    window.addEventListener("online", this.boundProbe)
    // If the browser later reports it dropped offline, revert the hint so a
    // stale 🟢 ("Back online") can't linger after the connection is gone.
    window.addEventListener("offline", this.boundOffline)
    // navigator.onLine === false means we're definitely offline — skip the doomed
    // probe and let the HTML's default "still offline" hint stand. The online
    // event re-probes when connectivity returns.
    if (navigator.onLine) this.probe()
  }

  disconnect() {
    this._stopped = true
    window.removeEventListener("online", this.boundProbe)
    window.removeEventListener("offline", this.boundOffline)
  }

  markOffline() {
    if (this._stopped || !this.hasStatusTarget) return
    this.statusTarget.textContent = "🔴 Still offline — your catches are saved"
  }

  back() {
    window.location.href = "/"
  }

  async probe() {
    if (this._probing || this._stopped) return
    this._probing = true
    let reachable = false
    const ctrl = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), 3000)
    try {
      // HEAD bypasses the service worker (it only handles GET), so this is a
      // truthful network probe. The timeout keeps the hint responsive on a
      // hanging connection rather than waiting for the browser's default.
      const res = await fetch("/", { method: "HEAD", cache: "no-store", signal: ctrl.signal })
      reachable = res.ok
    } catch {
      reachable = false
    } finally {
      clearTimeout(timer)
    }
    this._probing = false
    if (this._stopped || !this.hasStatusTarget) return
    this.statusTarget.textContent = reachable
      ? "🟢 Back online — tap to return"
      : "🔴 Still offline — your catches are saved"
  }
}
