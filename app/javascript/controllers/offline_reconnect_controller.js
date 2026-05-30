import { Controller } from "@hotwired/stimulus"

// On the cached /offline shell, a regained connection means we should leave the
// static shell for a real authenticated page. Reloading to "/" lets the normal
// page's offline/sync.js drain the queued catches with a valid session + CSRF
// token — the shell itself has neither and would 401 on upload.
export default class extends Controller {
  connect() {
    this.boundReconnect = () => this.reconnect()
    window.addEventListener("online", this.boundReconnect)
    // Belt-and-suspenders: if we somehow rendered the shell while already online
    // (e.g. a stale precache served on a flaky connection), leave immediately.
    if (navigator.onLine) this.reconnect()
  }

  disconnect() {
    window.removeEventListener("online", this.boundReconnect)
  }

  reconnect() {
    if (this._leaving) return
    this._leaving = true
    window.location.href = "/"
  }
}
