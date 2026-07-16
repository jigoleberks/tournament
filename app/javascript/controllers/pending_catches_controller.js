import { Controller } from "@hotwired/stimulus"
import { pendingCatches, failedCatches, markPending } from "offline/db"

// How long a catch may sit pending before we stop calling it "syncing" and
// start calling it stuck. Only affects whether the recovery link is offered.
const STUCK_AFTER_MS = 2 * 60 * 1000

export default class extends Controller {
  static targets = ["list", "empty", "failedList", "failedSection", "recoverLink"]

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
        <li>🕐 ${escapeHtml(p.length_inches)}″ — captured ${new Date(p.captured_at_device).toLocaleTimeString()}</li>
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
            <span>
              ⚠️ ${escapeHtml(f.length_inches)}″ — captured ${new Date(f.captured_at_device).toLocaleString()}
              ${f.reason ? `<span class="block text-xs text-amber-400">${escapeHtml(f.reason)}</span>` : ""}
            </span>
            <button type="button" data-action="pending-catches#retry" data-uuid="${escapeHtml(f.client_uuid)}"
                    class="h-9 px-3 rounded-lg bg-amber-600 active:bg-amber-700 text-white text-sm">Retry</button>
          </li>
        `).join("")
      }
    }

    // The link only exists when a site admin has enabled the recovery tool.
    // Reveal it only to anglers who actually have something stuck. A pending
    // catch counts, but only once it's old enough to look stuck rather than
    // merely in-flight — otherwise every normal log flashes the link for the
    // second or two drain() takes. A record with no queued_at predates that
    // field, so treat it as stuck: surfacing a healthy catch beats hiding a
    // stranded one.
    if (this.hasRecoverLinkTarget) {
      const now = Date.now()
      const stuckPending = pending.filter((p) => !p.queued_at || now - p.queued_at > STUCK_AFTER_MS)
      this.recoverLinkTarget.hidden = (stuckPending.length + failed.length) === 0
    }
  }

  async retry(event) {
    const uuid = event.currentTarget.dataset.uuid
    if (!uuid) return
    await markPending(uuid)
    window.dispatchEvent(new Event("bsfamilies:try-sync"))
    await this.refresh()
  }
}

// Everything rendered here comes out of IndexedDB — our own records, plus a
// reason string that may be a server error body — and is interpolated into
// innerHTML, so escape it rather than trusting it as markup. Applied to every
// interpolated value, not just the reason: these are all app-written and only
// reachable on the angler's own device, so the risk is self-inflicted at
// worst, but a half-escaped template reads as though the bare ones were
// vetted and invites the next one to be added unescaped.
function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => (
    { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]
  ))
}
