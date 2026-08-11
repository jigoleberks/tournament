import { Controller } from "@hotwired/stimulus"
import { fetchSession } from "offline/session"

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
    if (this._modalObserver) {
      this._modalObserver.disconnect()
      this._modalObserver = null
    }
  }

  async refresh() {
    // A replace-visit would wipe an open catch-photo modal (the frame
    // re-renders empty) and the photo the viewer is inspecting with it. Wait
    // for the modal to close (its close button empties the frame), then
    // refresh — the missed broadcasts still get picked up.
    const modal = document.querySelector("turbo-frame#catch_photo_modal")
    if (modal && modal.childElementCount > 0) {
      this.refreshWhenModalCloses(modal)
      return
    }
    // Probe reachability before visiting. Offline, the SW answers fetches
    // with a 503 (or the /offline shell), and a replace-visit would wipe a
    // stale-but-readable leaderboard — and its history entry — with it.
    // navigator.onLine can't be trusted here (see the note in offline/sync.js:
    // WebKit's flag goes stale after backgrounding), so a real fetch is the
    // check.
    //
    // Probe /api/session rather than this page: a HEAD to the leaderboard runs
    // the whole stack and only discards the body at Rack::Head, so it costs a
    // full Leaderboards::Build and ERB render — and the Turbo.visit below then
    // renders it a SECOND time. Every foreground, bfcache restore and
    // edge-swipe paid double, on the one VM, exactly when a tournament night
    // has thirty phones cycling in and out.
    //
    // Only "ok" may proceed. "authRequired" is the expired-session case (an
    // Api::BaseController 401, so no redirect: "manual" trick is needed here —
    // the status carries the signal, unlike this page's require_sign_in! 302
    // to a 200 sign-in screen). "network"/"unavailable" are offline or a
    // broken endpoint; both keep the snapshot and let the next foreground
    // retry. Every page mounting this controller is behind
    // TournamentsController's require_sign_in!, so treating authRequired as
    // "don't refresh" can't strand an anonymous viewer — there isn't one.
    //
    // Trade: this no longer validates THIS page specifically, so a leaderboard
    // that 500s while the rest of the app is healthy now gets visited (and the
    // error page renders over the snapshot) where the HEAD would have caught
    // it. Accepted — that is a rare already-broken state, against a cost paid
    // on every single refresh.
    const session = await fetchSession()
    if (session.state !== "ok") return
    if (window.Turbo) {
      // A replace-visit resets scroll to top; put the viewer back where they
      // were (mid-leaderboard) once the fresh page renders. Guarded on the
      // URL so the one-shot listener can't scroll some later page the user
      // navigated to instead.
      const scrollY = window.scrollY
      const href = window.location.href
      const restoreScroll = () => {
        if (window.location.href === href) window.scrollTo(0, scrollY)
      }
      document.addEventListener("turbo:load", restoreScroll, { once: true })
      // If the visit dies between the reachability probe and its own fetch
      // (1-bar lake LTE), turbo:load never fires and the armed listener would
      // scroll-jack the user's NEXT real visit to this URL — disarm it once
      // the visit is plainly dead.
      setTimeout(() => document.removeEventListener("turbo:load", restoreScroll), 15000)
      window.Turbo.visit(href, { action: "replace" })
    } else {
      window.location.reload()
    }
  }

  refreshWhenModalCloses(modal) {
    if (this._modalObserver) return
    this._modalObserver = new MutationObserver(() => {
      if (modal.childElementCount > 0) return
      this._modalObserver.disconnect()
      this._modalObserver = null
      this.refresh()
    })
    this._modalObserver.observe(modal, { childList: true })
  }
}
