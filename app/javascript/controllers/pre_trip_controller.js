import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["session", "tournaments", "camera", "microphone", "gps", "clock", "notifications", "network"]
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
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          const acc = pos.coords.accuracy
          if (acc <= 50) this.set("gps", `✓ ${acc.toFixed(0)}m`)
          else if (acc <= 200) this.set("gps", `⚠ ${acc.toFixed(0)}m (low)`)
          else this.set("gps", `✗ ${acc.toFixed(0)}m`)
          this.checkClock(pos.timestamp)
          resolve()
        },
        () => { this.set("gps", "✗ no fix"); this.set("clock", "⚠ no GPS clock"); resolve() },
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
}
