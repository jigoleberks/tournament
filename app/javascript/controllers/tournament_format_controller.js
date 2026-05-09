import { Controller } from "@hotwired/stimulus"

// Toggles the tournament form UI when format changes.
//
// big_fish_season:
//   - mode select: forced to "solo" and visually locked (no actual `disabled` attr,
//     so the value still submits)
//   - scoring slots: hide all but the first row. Persisted extras are marked for
//     destruction so accepts_nested_attributes_for removes them on save; new
//     extras have their species cleared so reject_if drops them.
//
// standard: restore the default UI, including unchecking only the destroy
// checkboxes we marked ourselves (so user-driven removals are preserved).
export default class extends Controller {
  static targets = [
    "format", "formatDescription",
    "mode", "modeNote",
    "slotsHeading", "slotsHelp", "slotRow", "slotCountLabel"
  ]

  connect() {
    if (this.hasModeTarget) this._priorMode = this.modeTarget.value
    this.sync()
  }

  sync() {
    if (this.formatTarget.value === "big_fish_season") {
      this._applyBigFishSeason()
    } else if (this.formatTarget.value === "hidden_length") {
      this._applyHiddenLength()
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
        if (i > 0) this._suppressRow(el)
      })
    }
  }

  _applyHiddenLength() {
    if (this.hasFormatDescriptionTarget) {
      this.formatDescriptionTarget.textContent = this.formatDescriptionTarget.dataset.hiddenLengthText
    }
    if (this.hasModeTarget) {
      // Hidden Length allows both solo and team — no lock, no forced value.
      this.modeTarget.classList.remove("opacity-60", "pointer-events-none")
      if (this._priorMode) {
        this.modeTarget.value = this._priorMode
        this._priorMode = null
      }
    }
    if (this.hasModeNoteTarget) this.modeNoteTarget.classList.add("hidden")

    if (this.hasSlotsHeadingTarget) this.slotsHeadingTarget.textContent = "Species configuration"
    if (this.hasSlotsHelpTarget) {
      this.slotsHelpTarget.textContent = "Pick the one species this tournament covers. The slot count is ignored — every catch is kept until the target is rolled at the end."
    }
    if (this.hasSlotCountLabelTarget) {
      this.slotCountLabelTargets.forEach((el) => { el.textContent = "Slots (ignored)" })
    }

    if (this.hasSlotRowTarget) {
      this.slotRowTargets.forEach((el, i) => {
        el.classList.toggle("hidden", i > 0)
        if (i > 0) this._suppressRow(el)
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
      this.slotRowTargets.forEach((el) => {
        el.classList.remove("hidden")
        this._unsuppressRow(el)
      })
    }
  }

  _suppressRow(el) {
    const destroy = el.querySelector('input[type="checkbox"][name$="[_destroy]"]')
    if (destroy && !destroy.checked) {
      destroy.checked = true
      el.dataset.tournamentFormatMarkedDestroy = "true"
    }
    const speciesSelect = el.querySelector('select[name$="[species_id]"]')
    if (speciesSelect) speciesSelect.value = ""
  }

  _unsuppressRow(el) {
    if (el.dataset.tournamentFormatMarkedDestroy === "true") {
      const destroy = el.querySelector('input[type="checkbox"][name$="[_destroy]"]')
      if (destroy) destroy.checked = false
      delete el.dataset.tournamentFormatMarkedDestroy
    }
  }
}
