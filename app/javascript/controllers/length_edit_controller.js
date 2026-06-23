import { Controller } from "@hotwired/stimulus"
import { convertLength, snapToGrid } from "lib/length_convert"

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
      // Snap to the new unit's 0.25 grid so the form passes HTML5 stepMismatch
      // validation on submit (the form is local: true).
      this.inputTarget.value = snapToGrid(convertLength(v, oldUnit, newUnit)).toFixed(2)
    }

    this.inputTarget.dataset.lengthEditUnit = newUnit
    this.inputTarget.step = "0.25"
  }
}
