import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "caret"]
  static values  = { open: Boolean }

  toggle(event) {
    event.preventDefault()
    this.openValue = !this.openValue
    this.panelTarget.classList.toggle("hidden", !this.openValue)
    if (this.hasCaretTarget) {
      this.caretTarget.textContent = this.openValue ? "▾" : "▸"
    }
    event.currentTarget.setAttribute("aria-expanded", String(this.openValue))
    this.syncUrl()
  }

  syncUrl() {
    const url = new URL(window.location.href)
    if (this.openValue) {
      url.searchParams.set("mc", "open")
    } else {
      url.searchParams.delete("mc")
    }
    window.history.replaceState({}, "", url)
  }
}
