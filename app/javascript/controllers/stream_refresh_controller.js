import { Controller } from "@hotwired/stimulus"

// iOS kills the Action Cable socket while the PWA is backgrounded, and Turbo
// Stream broadcasts sent meanwhile are never replayed — a foregrounded
// leaderboard can be arbitrarily stale with no indicator, and the one-shot
// blind-reveal broadcast at ends_at is missed entirely by anyone whose phone
// was asleep (i.e. everyone on the water). Re-visit the page on foreground so
// it re-renders from the server. The 15s floor avoids churn on quick
// app-switches where the socket usually survives.
const STALE_AFTER_MS = 15000

// In standalone mode there is no toolbar: users navigate by edge-swipe, which
// Turbo services as a *restoration* visit — snapshot render, no server round
// trip — so broadcasts missed while on the other page are never replayed
// either. Track the visit action at module level so connect() can tell a
// restore apart from a fresh visit and re-render from the server.
let lastVisitAction = null
document.addEventListener("turbo:visit", (e) => { lastVisitAction = e.detail.action })

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
    if (lastVisitAction === "restore") {
      lastVisitAction = null
      this.refresh()
    }
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("pageshow", this.onPageshow)
  }

  async refresh() {
    // Probe reachability before visiting. Offline, the SW answers fetches
    // with a 503 (or the /offline shell), and a replace-visit would wipe a
    // stale-but-readable leaderboard — and its history entry — with it.
    // navigator.onLine can't be trusted here (see the note in offline/sync.js:
    // WebKit's flag goes stale after backgrounding), so a real fetch is the
    // check: not-ok or thrown → stay on the snapshot; the next foreground
    // retries.
    try {
      const resp = await fetch(window.location.href, {
        method: "HEAD", cache: "no-store", credentials: "same-origin"
      })
      if (!resp.ok) return
    } catch (_) {
      return
    }
    if (window.Turbo) {
      window.Turbo.visit(window.location.href, { action: "replace" })
    } else {
      window.location.reload()
    }
  }
}
