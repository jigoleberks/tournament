import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["session", "tournaments", "camera", "microphone", "gps", "clock", "notifications", "network", "version", "troubleshootStatus"]
  static values = { activeTournaments: Number }

  connect() { this.runAll() }

  async runAll() {
    this._reset()
    this.set("session", "✓")
    this.set("tournaments", this.activeTournamentsValue > 0 ? "✓" : "⚠ no active tournaments today")
    await this.checkCamera()
    await this.checkMicrophone()
    await this.checkGps()
    await this.checkNotifications()
    this.set("network", navigator.onLine ? `✓ (${navigator.connection?.effectiveType ?? "online"})` : "ℹ offline (sync deferred)")
    await this.checkVersion()
  }

  // Compares the build the phone actually has cached against the live server
  // build. The page is a network-first navigation, so data-app-build is the
  // current server version; the installed shell version lives in the
  // `shell-<build>` Cache Storage key (see pwa/service_worker.js.erb). When they
  // differ the PWA is stuck on an old deploy and "Update app" below is the fix.
  async checkVersion() {
    const server = document.documentElement.dataset.appBuild || ""
    let loaded = server
    try {
      if ("caches" in window) {
        const shell = (await caches.keys()).find((k) => k.startsWith("shell-"))
        if (shell) loaded = shell.slice("shell-".length)
      }
    } catch (e) {
      // Cache Storage unavailable (e.g. private mode): fall back to assuming the
      // page render is current rather than crying stale on a number we can't read.
    }
    const short = (v) => v.slice(0, 7) || "unknown"
    if (loaded === server) {
      this.set("version", `✓ ${short(server)}`)
    } else {
      this.set("version", `⚠ update available — you: ${short(loaded)} · server: ${short(server)}`)
    }
  }

  _reset() {
    for (const name of this.constructor.targets) {
      this.set(name, "…")
    }
  }

  set(name, text) { this[`${name}Target`].textContent = text }

  async checkCamera() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } })
      stream.getTracks().forEach((t) => t.stop())
      this.set("camera", "✓")
    } catch (e) { this.set("camera", `✗ ${e.message}`) }
  }

  async checkMicrophone() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      stream.getTracks().forEach((t) => t.stop())
      this.set("microphone", "✓")
    } catch (e) { this.set("microphone", `✗ ${e.message}`) }
  }

  checkGps() {
    return new Promise((resolve) => {
      if (!navigator.geolocation) { this.set("gps", "✗ no API"); this.set("clock", "⚠ no GPS clock"); return resolve() }
      // Safety timeout: some browsers never fire success or error.
      const safetyTimeout = setTimeout(() => {
        this.set("gps", "✗ no fix (timeout)")
        this.set("clock", "⚠ no GPS clock")
        resolve()
      }, 10000)
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          clearTimeout(safetyTimeout)
          const acc = pos.coords.accuracy
          if (acc <= 50) this.set("gps", `✓ ${acc.toFixed(0)}m`)
          else if (acc <= 200) this.set("gps", `⚠ ${acc.toFixed(0)}m (low)`)
          else this.set("gps", `✗ ${acc.toFixed(0)}m`)
          this.checkClock(pos.timestamp)
          resolve()
        },
        () => {
          clearTimeout(safetyTimeout)
          this.set("gps", "✗ no fix")
          this.set("clock", "⚠ no GPS clock")
          resolve()
        },
        { enableHighAccuracy: true, timeout: 8000 }
      )
    })
  }

  checkClock(gpsMillis) {
    const skewMs = Math.abs(Date.now() - gpsMillis)
    if (skewMs <= 5 * 60 * 1000) this.set("clock", `✓ ${(skewMs / 1000).toFixed(0)}s skew`)
    else this.set("clock", `✗ ${Math.round(skewMs / 60000)}m skew (> 5)`)
  }

  async checkNotifications() {
    if (!("Notification" in window)) return this.set("notifications", "⚠ unsupported")
    if (Notification.permission === "granted") return this.set("notifications", "✓")
    if (Notification.permission === "denied")  return this.set("notifications", "⚠ denied")
    return this.set("notifications", "⚠ not requested yet")
  }

  // Forces a fresh copy of the app: unregister the service worker and drop every
  // Cache Storage entry (the precached shell + fingerprinted assets), then reload
  // so a clean worker reinstalls. Recovers a phone stuck on an old deploy or a
  // broken offline shell. The offline catch queue lives in IndexedDB, which we
  // deliberately leave untouched — pending catches survive the reset.
  async updateApp() {
    this._troubleshoot("Updating…")
    try {
      if ("serviceWorker" in navigator) {
        const regs = await navigator.serviceWorker.getRegistrations()
        await Promise.all(regs.map((r) => r.unregister()))
      }
      if ("caches" in window) {
        const keys = await caches.keys()
        await Promise.all(keys.map((k) => caches.delete(k)))
      }
    } catch (e) {
      console.warn("App update/clear-cache failed:", e)
    }
    location.reload()
  }

  _troubleshoot(text) {
    if (this.hasTroubleshootStatusTarget) this.troubleshootStatusTarget.textContent = text
  }
}
