import { Controller } from "@hotwired/stimulus"

// Re-fetches the leaderboard turbo-frame when the cable subscription (re)connects
// or when the tab becomes visible again. Action Cable does not replay broadcasts
// missed during a disconnect, so this is the recovery path for mobile browsers
// that suspend the websocket while the page is backgrounded.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.boundReload = this.reload.bind(this)
    this.boundVisibility = this.onVisibilityChange.bind(this)
    document.addEventListener("turbo:cable-stream-source-connected", this.boundReload)
    document.addEventListener("visibilitychange", this.boundVisibility)
  }

  disconnect() {
    document.removeEventListener("turbo:cable-stream-source-connected", this.boundReload)
    document.removeEventListener("visibilitychange", this.boundVisibility)
  }

  onVisibilityChange() {
    if (document.visibilityState === "visible") this.reload()
  }

  reload() {
    if (!this.urlValue) return
    this.element.src = this.urlValue
  }
}
