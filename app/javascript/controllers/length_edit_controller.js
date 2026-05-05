import { Controller } from "@hotwired/stimulus"

// Live-converts the bound number input between inches and centimeters when
// a sibling unit radio changes. Used on the catch show page's edit-length
// form. Does NOT persist the unit choice — this form is used by judges and
// organizers to edit other members' fish, so the toggle is intentionally
// transient and must not change the current user's saved length_unit.
export default class extends Controller {
  static targets = ["input"]

  convertUnit(event) {
    const newUnit = event.target.value
    const oldUnit = this.inputTarget.dataset.lengthEditUnit
    if (oldUnit === newUnit) return

    const v = parseFloat(this.inputTarget.value)
    if (!Number.isNaN(v)) {
      const factor = oldUnit === "inches" && newUnit === "centimeters" ? 2.54
                   : oldUnit === "centimeters" && newUnit === "inches" ? 1 / 2.54
                   : 1
      this.inputTarget.value = (v * factor).toFixed(2)
    }

    this.inputTarget.dataset.lengthEditUnit = newUnit
    this.inputTarget.step = newUnit === "centimeters" ? "0.5" : "0.25"
  }
}
