import { Controller } from "@hotwired/stimulus"

// One chip row bound to one text field. Tapping a chip fills the field;
// tapping it again clears it; "Other…" reveals the field for free typing.
// The field keeps its normal name so the form submits unchanged.
const ACTIVE = ["bg-blue-600", "text-white"]
const IDLE = ["bg-slate-700", "text-slate-100"]

export default class extends Controller {
  static targets = ["chip", "input", "otherButton"]

  connect() {
    const current = this.inputTarget.value.trim()
    const match = this._chipFor(current)
    if (match) {
      this._activate(match)
    } else if (current) {
      this._showInput()
    }
  }

  pick(event) {
    const chip = event.currentTarget
    const already = this.inputTarget.value.trim().toLowerCase() === chip.dataset.value.toLowerCase()
    this._setValue(already ? "" : chip.dataset.value)
    this._clearChips()
    if (!already) {
      this._activate(chip)
      this._hideInput()
    }
  }

  other() {
    this._setValue("")
    this._clearChips()
    this._showInput()
    this.inputTarget.focus()
  }

  typed() {
    this._clearChips()
    const match = this._chipFor(this.inputTarget.value.trim())
    if (match) this._activate(match)
  }

  _chipFor(value) {
    if (!value) return null
    return this.chipTargets.find(c => c.dataset.value.toLowerCase() === value.toLowerCase())
  }

  _setValue(value) {
    this.inputTarget.value = value
    // Programmatic assignment doesn't fire input events; dispatch one so the
    // surrounding bait-preview controller sees the change.
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  _activate(chip) {
    chip.classList.remove(...IDLE)
    chip.classList.add(...ACTIVE)
  }

  _clearChips() {
    this.chipTargets.forEach(c => {
      c.classList.remove(...ACTIVE)
      c.classList.add(...IDLE)
    })
  }

  _showInput() {
    this.inputTarget.classList.remove("hidden")
  }

  _hideInput() {
    this.inputTarget.classList.add("hidden")
  }
}
