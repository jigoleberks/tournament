import { Controller } from "@hotwired/stimulus"
import { pendingCatches, failedCatches, markPending, removeRecord } from "offline/db"

export default class extends Controller {
  static targets = ["list", "empty", "failedList", "failedSection"]

  async connect() {
    this.boundRefresh = () => this.refresh()
    window.addEventListener("bsfamilies:catch-synced", this.boundRefresh)
    window.addEventListener("bsfamilies:catch-failed", this.boundRefresh)
    await this.refresh()
  }

  disconnect() {
    window.removeEventListener("bsfamilies:catch-synced", this.boundRefresh)
    window.removeEventListener("bsfamilies:catch-failed", this.boundRefresh)
  }

  async refresh() {
    const [pending, failed] = await Promise.all([pendingCatches(), failedCatches()])

    if (pending.length === 0) {
      this.listTarget.innerHTML = ""
      this.emptyTarget.hidden = failed.length > 0
    } else {
      this.emptyTarget.hidden = true
      this.listTarget.innerHTML = pending.map((p) => `
        <li>🕐 ${p.length_inches}″ — captured ${new Date(p.captured_at_device).toLocaleTimeString()}</li>
      `).join("")
    }

    if (this.hasFailedSectionTarget) {
      if (failed.length === 0) {
        this.failedSectionTarget.hidden = true
        this.failedListTarget.innerHTML = ""
      } else {
        this.failedSectionTarget.hidden = false
        this.failedListTarget.innerHTML = failed.map((f) => `
          <li class="flex items-center justify-between gap-2 py-1">
            <span>⚠️ ${f.length_inches}″ — captured ${new Date(f.captured_at_device).toLocaleString()}</span>
            <span class="flex gap-1">
              <button type="button" data-action="pending-catches#retry" data-uuid="${f.client_uuid}"
                      class="h-9 px-3 rounded-lg bg-amber-600 active:bg-amber-700 text-white text-sm">Retry</button>
              <button type="button" data-action="pending-catches#dismiss" data-uuid="${f.client_uuid}"
                      class="h-9 px-3 rounded-lg bg-slate-700 active:bg-slate-600 text-slate-100 text-sm">Dismiss</button>
            </span>
          </li>
        `).join("")
      }
    }
  }

  async retry(event) {
    const uuid = event.currentTarget.dataset.uuid
    if (!uuid) return
    await markPending(uuid)
    window.dispatchEvent(new Event("bsfamilies:try-sync"))
    await this.refresh()
  }

  async dismiss(event) {
    const uuid = event.currentTarget.dataset.uuid
    if (!uuid) return
    await removeRecord(uuid)
    await this.refresh()
  }
}
