import { Controller } from "@hotwired/stimulus"
import { pendingCatches, failedCatches, markSynced } from "offline/db"
import { materialize } from "offline/blob"
import { buildCatchFormData } from "offline/form_data"
import { fetchSession } from "offline/session"

// Reads stuck catch records from IndexedDB, re-materializes each photo blob
// (see offline/blob.js for why), shows a thumbnail, and re-submits via the
// normal /api/catches path using the record's ORIGINAL client_uuid so the
// server's dedup makes a double-tap harmless.
export default class extends Controller {
  static targets = ["list", "empty", "error"]

  async connect() {
    // Turbo Drive restores a cached snapshot (including previously rendered
    // <li>s) on a back-navigation visit, and connect() runs again on top of
    // it. Without clearing first, we'd append a second set of rows whose
    // blob URLs are revoked and whose "Re-submit" buttons carry no listeners
    // (addEventListener doesn't survive into a snapshot) — dead buttons on
    // the exact screen an angler mid-recovery is tapping.
    this.listTarget.innerHTML = ""
    if (this.hasEmptyTarget) this.emptyTarget.hidden = true
    if (this.hasErrorTarget) this.errorTarget.hidden = true
    this.objectUrls = []
    // This render loop awaits once per row, so a navigation can land between
    // rows — or mid-row, while rematerialize() is still reading bytes. Every
    // step past an await is guarded on this token so a superseded run stops
    // instead of racing the live one. disconnect() bumps it too.
    const gen = this.generation = (this.generation || 0) + 1
    try {
      const records = [...await pendingCatches(), ...await failedCatches()]
      if (gen !== this.generation) return
      if (records.length === 0) {
        if (this.hasEmptyTarget) this.emptyTarget.hidden = false
        return
      }
      for (const rec of records) {
        if (gen !== this.generation) return
        await this.renderRow(rec, gen)
      }
    } catch (e) {
      if (gen !== this.generation) return
      if (this.hasErrorTarget) {
        this.errorTarget.hidden = false
        this.errorTarget.textContent = `Could not read saved catches on this device: ${e}`
      }
    }
  }

  disconnect() {
    // Bumping the token strands any in-flight connect(): it returns before
    // creating a URL rather than pushing one into an array we've already
    // drained, which would leak it for the life of the document.
    this.generation = (this.generation || 0) + 1
    ;(this.objectUrls || []).forEach((u) => URL.revokeObjectURL(u))
    this.objectUrls = []
  }

  async renderRow(rec, gen) {
    const li = document.createElement("li")
    li.className = "flex flex-wrap items-center gap-3 py-2 border-b border-slate-700"

    const info = document.createElement("div")
    info.className = "flex-1 min-w-0 text-sm text-slate-200"
    const size = rec.photo ? rec.photo.size : 0
    info.textContent = `${rec.length_inches}″ — ${new Date(rec.captured_at_device).toLocaleString()} · ${size} bytes`

    const fresh = await materialize(rec.photo)
    // Bail before createObjectURL, not after: a URL minted now would be pushed
    // into an objectUrls array that disconnect() has already drained.
    if (gen !== this.generation) return
    if (!fresh) {
      const dead = document.createElement("span")
      dead.className = "text-amber-400 text-sm"
      dead.textContent = "PHOTO UNREADABLE"
      li.append(info, dead)
      this.listTarget.appendChild(li)
      return
    }

    const url = URL.createObjectURL(fresh)
    this.objectUrls.push(url)

    const img = document.createElement("img")
    img.src = url
    img.className = "w-16 h-16 object-cover rounded bg-slate-700"

    const dl = document.createElement("a")
    dl.href = url
    dl.download = `${rec.client_uuid}.${this.extensionFor(fresh.type)}`
    dl.textContent = "Download"
    dl.className = "h-9 px-3 rounded-lg bg-slate-700 text-slate-100 text-sm flex items-center"

    const btn = document.createElement("button")
    btn.type = "button"
    btn.textContent = "Re-submit"
    btn.className = "h-9 px-3 rounded-lg bg-emerald-600 active:bg-emerald-700 text-white text-sm"
    btn.addEventListener("click", () => this.resubmit(rec, fresh, li, btn))

    li.append(img, info, dl, btn)
    this.listTarget.appendChild(li)
  }

  extensionFor(type) {
    if (!type) return "jpg"
    if (type.includes("png")) return "png"
    if (type.includes("webp")) return "webp"
    if (type.includes("heic")) return "heic"
    if (type.includes("heif")) return "heif"
    return "jpg"
  }

  async resubmit(rec, fresh, li, btn) {
    btn.disabled = true
    btn.textContent = "Sending…"

    const fd = await buildCatchFormData(rec, fresh, `recovered.${this.extensionFor(fresh.type)}`)

    // Preflight (offline/session.js): iOS restores this page from the
    // bfcache with a stale CSRF meta token, and re-submitting with it fails on
    // every tap until a hard reload — on the tool of last resort. A fresh
    // token fixes that; the meta token is only the flake/broken fallback.
    const preflight = await fetchSession()
    if (preflight.state === "authRequired") {
      btn.disabled = false
      btn.textContent = "Retry"
      this.showError(li, "You're signed out — sign in, then tap Re-submit again.")
      return
    }
    const csrf = preflight.state === "ok" ? preflight.csrf_token : this.csrfToken()

    try {
      const resp = await fetch("/api/catches", {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": csrf },
        body: fd,
        credentials: "same-origin"
      })
      if (resp.ok) {
        await markSynced(rec.client_uuid)
        li.classList.add("opacity-60")
        btn.disabled = true
        btn.textContent = "Recovered ✓"
        btn.className = "h-9 px-3 rounded-lg bg-emerald-800 text-white text-sm"
      } else {
        // Same extraction as offline/sync.js: the API's refusals (including
        // the shared-phone queued_by_mismatch) arrive as {errors: [...]}
        // JSON, and showing that raw — truncated mid-sentence — garbles the
        // one actionable instruction on the tool of last resort. Non-JSON
        // (reverse-proxy 413 page, etc.) still falls back to a snippet.
        const text = await resp.text().catch(() => "")
        let body = null
        try { body = JSON.parse(text) } catch (_) {}
        const reason = body && Array.isArray(body.errors) && body.errors.length
          ? body.errors.join(", ")
          : `Server ${resp.status}: ${text.slice(0, 120)}`
        btn.disabled = false
        btn.textContent = "Retry"
        this.showError(li, reason)
      }
    } catch (e) {
      btn.disabled = false
      btn.textContent = "Retry"
      this.showError(li, `Network error: ${e}`)
    }
  }

  showError(li, msg) {
    let err = li.querySelector(".recover-error")
    if (!err) {
      err = document.createElement("div")
      err.className = "recover-error text-amber-400 text-xs w-full"
      li.appendChild(err)
    }
    err.textContent = msg
  }

  csrfToken() {
    const el = document.querySelector("meta[name='csrf-token']")
    return el ? el.content : ""
  }
}
