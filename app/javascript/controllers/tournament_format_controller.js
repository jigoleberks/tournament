import { Controller } from "@hotwired/stimulus"

// Toggles the tournament form UI when format changes.
//
// big_fish_season:
//   - mode select: forced to "solo" and visually locked (no actual `disabled` attr,
//     so the value still submits)
//   - scoring slots: hide all but the first row; relabel section + slot count label
//
// standard: restore the default UI.
export default class extends Controller {
  static targets = [
    "format", "formatDescription",
    "mode", "modeNote",
    "slotsHeading", "slotsHelp", "slotRow", "slotCountLabel"
  ]

  connect() {
    this.sync()
  }

  sync() {
    if (this.formatTarget.value === "big_fish_season") {
      this._applyBigFishSeason()
    } else {
      this._applyStandard()
    }
  }

  _applyBigFishSeason() {
    if (this.hasFormatDescriptionTarget) {
      this.formatDescriptionTarget.textContent = this.formatDescriptionTarget.dataset.bigFishSeasonText
    }
    if (this.hasModeTarget) {
      if (this.modeTarget.value !== "solo") this._priorMode = this.modeTarget.value
      this.modeTarget.value = "solo"
      this.modeTarget.classList.add("opacity-60", "pointer-events-none")
    }
    if (this.hasModeNoteTarget) this.modeNoteTarget.classList.remove("hidden")

    if (this.hasSlotsHeadingTarget) this.slotsHeadingTarget.textContent = "Species configuration"
    if (this.hasSlotsHelpTarget) {
      this.slotsHelpTarget.textContent = "Pick the species and how many of each member's biggest fish to display. These same fish are used for tiebreak (1st biggest, then 2nd biggest, etc.)."
    }
    if (this.hasSlotCountLabelTarget) {
      this.slotCountLabelTargets.forEach((el) => { el.textContent = "Top fish per member to display" })
    }

    if (this.hasSlotRowTarget) {
      this.slotRowTargets.forEach((el, i) => {
        el.classList.toggle("hidden", i > 0)
        // Clear species selection on hidden rows so they get rejected by accepts_nested_attributes_for.
        if (i > 0) {
          const speciesSelect = el.querySelector('select[name$="[species_id]"]')
          if (speciesSelect) speciesSelect.value = ""
        }
      })
    }
  }

  _applyStandard() {
    if (this.hasFormatDescriptionTarget) {
      this.formatDescriptionTarget.textContent = this.formatDescriptionTarget.dataset.standardText
    }
    if (this.hasModeTarget) {
      this.modeTarget.classList.remove("opacity-60", "pointer-events-none")
      if (this._priorMode) {
        this.modeTarget.value = this._priorMode
        this._priorMode = null
      }
    }
    if (this.hasModeNoteTarget) this.modeNoteTarget.classList.add("hidden")

    if (this.hasSlotsHeadingTarget) this.slotsHeadingTarget.textContent = "Scoring slots"
    if (this.hasSlotsHelpTarget) {
      this.slotsHelpTarget.textContent = "Pick a species and how many of that fish counts. Blank rows are ignored."
    }
    if (this.hasSlotCountLabelTarget) {
      this.slotCountLabelTargets.forEach((el) => { el.textContent = "Slots" })
    }

    if (this.hasSlotRowTarget) {
      this.slotRowTargets.forEach((el) => el.classList.remove("hidden"))
    }
  }
}
