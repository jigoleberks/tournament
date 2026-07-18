import { Controller } from "@hotwired/stimulus"

// iOS kills the Action Cable socket while the PWA is backgrounded, and Turbo
// Stream broadcasts sent meanwhile are never replayed — a foregrounded
// leaderboard can be arbitrarily stale with no indicator, and the one-shot
// blind-reveal broadcast at ends_at is missed entirely by anyone whose phone
// was asleep (i.e. everyone on the water). Re-visit the page on foreground so
// it re-renders from the server. The 15s floor avoids churn on quick
// app-switches where the socket usually survives.
const STALE_AFTER_MS = 15000

export default class extends Controller {
  connect() {
    this.hiddenAt = null
    this.onVisibility = () => {
      if (document.visibilityState === "hidden") {
        this.hiddenAt = Date.now()
        return
      }
      if (this.hiddenAt && Date.now() - this.hiddenAt > STALE_AFTER_MS) this.refresh()
      this.hiddenAt = null
    }
    this.onPageshow = (e) => { if (e.persisted) this.refresh() }
    document.addEventListener("visibilitychange", this.onVisibility)
    window.addEventListener("pageshow", this.onPageshow)
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("pageshow", this.onPageshow)
  }

  refresh() {
    if (window.Turbo) {
      window.Turbo.visit(window.location.href, { action: "replace" })
    } else {
      window.location.reload()
    }
  }
}
