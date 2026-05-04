import { Controller } from "@hotwired/stimulus"

// Converts the displayed length input when the cm/in radio toggles so the
// number always matches the selected unit. Used by the override form on
// catches/show and judges/manual_overrides/new.
export default class extends Controller {
  static targets = ["input"]

  setUnit(event) {
    const newUnit = event.target.value
    const oldUnit = this.inputTarget.dataset.lengthUnitUnit
    if (oldUnit === newUnit) return

    const v = parseFloat(this.inputTarget.value)
    if (!Number.isNaN(v)) {
      const factor = oldUnit === "inches" && newUnit === "centimeters" ? 2.54
                   : oldUnit === "centimeters" && newUnit === "inches" ? 1 / 2.54
                   : 1
      this.inputTarget.value = (v * factor).toFixed(2)
    }

    this.inputTarget.dataset.lengthUnitUnit = newUnit
    this.inputTarget.step = newUnit === "centimeters" ? "0.5" : "0.25"
  }
}
