import { Controller } from "@hotwired/stimulus"
import { pendingCatches } from "offline/db"

export default class extends Controller {
  static targets = ["list", "empty"]

  async connect() {
    await this.refresh()
    window.addEventListener("bsfamilies:catch-synced", () => this.refresh())
  }

  async refresh() {
    const pending = await pendingCatches()
    if (pending.length === 0) {
      this.listTarget.innerHTML = ""
      this.emptyTarget.hidden = false
    } else {
      this.emptyTarget.hidden = true
      this.listTarget.innerHTML = pending.map((p) => `
        <li>🕐 ${p.length_inches}″ — captured ${new Date(p.captured_at_device).toLocaleTimeString()}</li>
      `).join("")
    }
  }
}
