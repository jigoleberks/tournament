import { Controller } from "@hotwired/stimulus"
import { pendingCatches, failedCatches, markPending } from "offline/db"
import { currentUserId } from "offline/current_user"

// How long a catch may sit pending before we stop calling it "syncing" and
// start calling it stuck. Only affects whether the recovery link is offered.
const STUCK_AFTER_MS = 2 * 60 * 1000

export default class extends Controller {
  static targets = ["list", "empty", "failedList", "failedSection", "recoverLink"]

  async connect() {
    this.boundRefresh = () => this.refresh()
    window.addEventListener("bsfamilies:catch-synced", this.boundRefresh)
    window.addEventListener("bsfamilies:catch-failed", this.boundRefresh)
    // Parking (deferRetry) is the third outcome a drain can produce, and the
    // only one the angler can act on while still on this page — see the
    // backoff notice below.
    window.addEventListener("bsfamilies:catch-deferred", this.boundRefresh)
    await this.refresh()
  }

  disconnect() {
    window.removeEventListener("bsfamilies:catch-synced", this.boundRefresh)
    window.removeEventListener("bsfamilies:catch-failed", this.boundRefresh)
    window.removeEventListener("bsfamilies:catch-deferred", this.boundRefresh)
  }

  async refresh() {
    // getDB can now reject rather than hang (another window holding the old
    // schema open — see offline/db.js). This widget is a status readout, so a
    // failed read leaves the last render up instead of throwing out of connect.
    let pending, failed
    try {
      [pending, failed] = await Promise.all([pendingCatches(), failedCatches()])
    } catch (_) {
      return
    }

    if (pending.length === 0) {
      this.listTarget.innerHTML = ""
      this.emptyTarget.hidden = failed.length > 0
    } else {
      this.emptyTarget.hidden = true
      // A record queued under a different account (shared phone) is silently
      // skipped by every drain — without the label it reads as a healthy
      // queue while the fish never uploads and nobody is told the fix.
      const me = currentUserId()
      const now = Date.now()
      this.listTarget.innerHTML = pending.map((p) => {
        const otherUser = p.queued_by_user_id && me && String(p.queued_by_user_id) !== String(me)
        // A record the server 5xx'd is held back by deferRetry for up to 15
        // minutes. Rendered as a bare 🕐 it is indistinguishable from a healthy
        // in-flight upload, so an angler watching a fish miss the leaderboard
        // has no idea it is waiting, let alone that they can hurry it.
        const waiting = !otherUser && p.next_attempt_at && p.next_attempt_at > now
        return `
        <li class="flex items-center justify-between gap-2 py-1">
          <span>
            🕐 ${escapeHtml(p.length_inches)}″ — captured ${new Date(p.captured_at_device).toLocaleTimeString()}
            ${otherUser ? '<span class="block text-xs text-amber-400">Logged under a different member’s account — it will sync when they sign in on this phone.</span>' : ""}
            ${waiting ? `<span class="block text-xs text-amber-400">Upload didn’t go through — retrying at ${new Date(p.next_attempt_at).toLocaleTimeString()}.</span>` : ""}
          </span>
          ${waiting ? `<button type="button" data-action="pending-catches#retry" data-uuid="${escapeHtml(p.client_uuid)}"
                    class="h-9 px-3 rounded-lg bg-amber-600 active:bg-amber-700 text-white text-sm shrink-0">Retry</button>` : ""}
        </li>`
      }).join("")
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
