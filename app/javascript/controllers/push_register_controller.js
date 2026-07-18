import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["enableButton", "status"]

  async connect() { this.refresh() }

  async refresh() {
    if (!("PushManager" in window)) {
      // iOS only exposes PushManager to installed home-screen apps: a plain
      // Safari tab must point at the fix (install), not read as broken.
      this.statusTarget.textContent = this.iosBrowserTab()
        ? "available after install — tap Share, then “Add to Home Screen”"
        : "push not supported"
      this.setEnabled(false)
      return
    }
    if (Notification.permission === "denied") {
      this.statusTarget.textContent = "blocked in browser"
      this.setEnabled(false)
      return
    }
    if (Notification.permission !== "granted") {
      this.statusTarget.textContent = "off"
      this.setEnabled(false)
      return
    }
    try {
      const reg = await withTimeout(navigator.serviceWorker.ready, 10000, "serviceWorker.ready")
      const sub = await reg.pushManager.getSubscription()
      this.statusTarget.textContent = sub ? "on" : "off"
      this.setEnabled(!!sub)
    } catch (_) {
      this.statusTarget.textContent = "service worker unavailable"
      this.setEnabled(false)
    }
  }

  // iPadOS 13+ masquerades as Macintosh in the UA; maxTouchPoints tells it apart.
  iosBrowserTab() {
    const ios = /iPhone|iPad|iPod/.test(navigator.userAgent) ||
      (/Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints > 1)
    const standalone = window.matchMedia("(display-mode: standalone)").matches ||
      window.navigator.standalone === true
    return ios && !standalone
  }

  setEnabled(on) {
    if (!this.hasEnableButtonTarget) return
    const btn = this.enableButtonTarget
    const blue   = ["bg-blue-600", "active:bg-blue-700", "text-white"]
    const slate  = ["bg-slate-700", "active:bg-slate-600", "text-slate-100"]
    btn.classList.remove(...(on ? slate : blue))
    btn.classList.add(...(on ? blue : slate))
  }

  async enable() {
    // In an iOS Safari tab neither Notification nor PushManager exists —
    // without this guard the tap surfaced a raw ReferenceError in the status.
    if (!("Notification" in window) || !("PushManager" in window)) {
      this.statusTarget.textContent = this.iosBrowserTab()
        ? "available after install — tap Share, then “Add to Home Screen”"
        : "push not supported on this browser"
      return
    }
    let step = "requestPermission"
    try {
      this.statusTarget.textContent = "asking permission…"
      const perm = await Notification.requestPermission()
      if (perm !== "granted") {
        this.statusTarget.textContent = `permission: ${perm}`
        return this.refresh()
      }

      step = "serviceWorker.ready"
      this.statusTarget.textContent = "waiting for worker…"
      const reg = await withTimeout(navigator.serviceWorker.ready, 10000, step)

      step = "pushManager.subscribe"
      this.statusTarget.textContent = "subscribing…"
      const sub = await withTimeout(reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlB64ToUint8Array(vapidPublicKey())
      }), 20000, step)

      step = "POST /api/push_subscriptions"
      this.statusTarget.textContent = "saving…"
      const res = await fetch("/api/push_subscriptions", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken() },
        credentials: "same-origin",
        body: JSON.stringify({ subscription: sub.toJSON() })
      })
      if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText}`)
      this.refresh()
    } catch (e) {
      const msg = `${step} failed: ${e.name || "Error"}: ${e.message || e}`
      this.statusTarget.textContent = msg
      console.error("push enable:", msg, e)
    }
  }

  async disable() {
    let reg
    try { reg = await withTimeout(navigator.serviceWorker.ready, 10000, "serviceWorker.ready") } catch (_) { return this.refresh() }
    const sub = await reg.pushManager.getSubscription()
    if (sub) {
      await sub.unsubscribe()
      await fetch("/api/push_subscriptions", {
        method: "DELETE",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken() },
        credentials: "same-origin",
        body: JSON.stringify({ endpoint: sub.endpoint })
      })
    }
    this.refresh()
  }
}

function vapidPublicKey() {
  return document.querySelector("meta[name='vapid-public-key']").content
}
function csrfToken() {
  return document.querySelector("meta[name='csrf-token']").content
}
function urlB64ToUint8Array(b64) {
  const padding = "=".repeat((4 - (b64.length % 4)) % 4)
  const base64 = (b64 + padding).replace(/-/g, "+").replace(/_/g, "/")
  const raw = atob(base64)
  return new Uint8Array([...raw].map((c) => c.charCodeAt(0)))
}
function withTimeout(promise, ms, label) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error(`timeout after ${ms}ms`)), ms))
  ])
}
