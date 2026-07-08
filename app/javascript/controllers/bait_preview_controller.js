import { Controller } from "@hotwired/stimulus"

// Live preview of Bait#display_name while the combo is being composed.
// Mirrors the server-side grouping: [weight color lure] + [plastic_color plastic] + [tipping].
export default class extends Controller {
  static targets = ["name", "weight", "color", "lure", "plastic", "plasticColor", "tipping"]

  connect() { this.refresh() }

  refresh() {
    const lure = [this._val("weight"), this._val("color"), this._val("lure")].filter(Boolean).join(" ")
    const plastic = [this._val("plasticColor"), this._val("plastic")].filter(Boolean).join(" ")
    const tipping = this._val("tipping")
    const groups = [lure, plastic, tipping].filter(Boolean)
    this.nameTarget.textContent = groups.length ? groups.join(" + ") : "Tap the pieces below to build your bait"
  }

  _val(name) {
    const target = this[`${name}Target`]
    return this[`has${name.charAt(0).toUpperCase()}${name.slice(1)}Target`] ? target.value.trim() : ""
  }
}
