import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["enableButton", "status"]

  async connect() { this.refresh() }

  async refresh() {
    if (!("PushManager" in window)) {
      this.statusTarget.textContent = "push not supported"
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
    const reg = await navigator.serviceWorker.ready
    const sub = await reg.pushManager.getSubscription()
    this.statusTarget.textContent = sub ? "on" : "off"
    this.setEnabled(!!sub)
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
    const perm = await Notification.requestPermission()
    if (perm !== "granted") return this.refresh()

    const reg = await navigator.serviceWorker.ready
    const sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlB64ToUint8Array(vapidPublicKey())
    })

    await fetch("/api/push_subscriptions", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken() },
      credentials: "same-origin",
      body: JSON.stringify({ subscription: sub.toJSON() })
    })
    this.refresh()
  }

  async disable() {
    const reg = await navigator.serviceWorker.ready
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
