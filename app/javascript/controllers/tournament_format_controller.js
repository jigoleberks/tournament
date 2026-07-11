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
    "slotsHeading", "slotsHelp", "slotRow", "slotCountLabel", "slotsSection",
    "trainBuilder",
    "localCheckbox",
    "blindCheckbox"
  ]

  connect() {
    if (this.hasModeTarget) this._priorMode = this.modeTarget.value
    this.sync()
    // Marks subsequent sync() calls as user-initiated. Used by _applyTagged
    // so we don't clobber a saved `local: true` on edit-form load.
    this._initialized = true
  }

  sync() {
    // Bingo is the only format that hides the whole slots section; default
    // it back to visible so switching away from Bingo restores it.
    if (this.hasSlotsSectionTarget) this.slotsSectionTarget.classList.remove("hidden")

    // Beat the Average is the only format that forces + locks the blind
    // checkbox. Unconditionally undo that before the per-format dispatch
    // below, so every format switch starts from a clean slate; if the new
    // format is Beat the Average again, _applyBeatTheAverage() re-forces it.
    this._restoreBlindCheckbox()

    if (this.formatTarget.value === "big_fish_season") {
      this._applyBigFishSeason()
    } else if (this.formatTarget.value === "hidden_length") {
      this._applyHiddenLength()
    } else if (this.formatTarget.value === "biggest_vs_smallest") {
      this._applyBiggestVsSmallest()
    } else if (this.formatTarget.value === "fish_train") {
      this._applyFishTrain()
    } else if (this.formatTarget.value === "tagged") {
      this._applyTagged()
    } else if (this.formatTarget.value === "smallest_fish") {
      this._applySmallestFish()
    } else if (this.formatTarget.value === "pro_walleye") {
      this._applyProWalleye()
    } else if (this.formatTarget.value === "bingo") {
      this._applyBingo()
    } else if (this.formatTarget.value === "progressive_length") {
      this._applyProgressiveLength()
    } else if (this.formatTarget.value === "beat_the_average") {
      this._applyBeatTheAverage()
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

    if (this.hasTrainBuilderTarget) this.trainBuilderTarget.classList.add("hidden")
  }

  _applyTagged() {
    if (this.hasFormatDescriptionTarget) {
      this.formatDescriptionTarget.textContent = this.formatDescriptionTarget.dataset.taggedText
    }
    if (this.hasModeTarget) {
      if (this.modeTarget.value !== "solo") this._priorMode = this.modeTarget.value
      this.modeTarget.value = "solo"
      this.modeTarget.classList.add("opacity-60", "pointer-events-none")
    }
    if (this.hasModeNoteTarget) this.modeNoteTarget.classList.remove("hidden")

    if (this.hasSlotsHeadingTarget) this.slotsHeadingTarget.textContent = "Species configuration"
    if (this.hasSlotsHelpTarget) {
      this.slotsHelpTarget.textContent = "Locked to Tagged Walleye. Each catch is one ticket in the end-of-tournament draw."
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

    if (this.hasTrainBuilderTarget) this.trainBuilderTarget.classList.add("hidden")

    // Tagged walleye raffles are typically province-wide (the science-tag
    // program isn't lake-restricted). Default `local` off on user-initiated
    // format change; preserve saved value on initial edit-form load.
    if (this.hasLocalCheckboxTarget && this._initialized) {
      this.localCheckboxTarget.checked = false
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

    if (this.hasTrainBuilderTarget) this.trainBuilderTarget.classList.add("hidden")
  }

  _applyFishTrain() {
    if (this.hasFormatDescriptionTarget) {
      this.formatDescriptionTarget.textContent = this.formatDescriptionTarget.dataset.fishTrainText
    }
    if (this.hasModeTarget) {
      // Fish Train allows solo or team — unlock and restore prior selection.
      this.modeTarget.classList.remove("opacity-60", "pointer-events-none")
      if (this._priorMode) {
        this.modeTarget.value = this._priorMode
        this._priorMode = null
      }
    }
    if (this.hasModeNoteTarget) this.modeNoteTarget.classList.add("hidden")

    if (this.hasSlotsHeadingTarget) this.slotsHeadingTarget.textContent = "Species pool"
    if (this.hasSlotsHelpTarget) {
      this.slotsHelpTarget.textContent = "Pick 1–3 species for the train pool. Slot counts are ignored — each car holds one fish."
    }
    if (this.hasSlotCountLabelTarget) {
      this.slotCountLabelTargets.forEach((el) => { el.textContent = "Slots (ignored)" })
    }

    // Cap pool to 3 species rows; hide rows beyond the 3rd.
    if (this.hasSlotRowTarget) {
      this.slotRowTargets.forEach((el, i) => {
        el.classList.toggle("hidden", i > 2)
        if (i > 2) this._suppressRow(el)
      })
    }

    // Reveal the train builder fieldset (added in Task 11).
    if (this.hasTrainBuilderTarget) {
      this.trainBuilderTarget.classList.remove("hidden")
    }
  }

  _applyBiggestVsSmallest() {
    if (this.hasFormatDescriptionTarget) {
      this.formatDescriptionTarget.textContent = this.formatDescriptionTarget.dataset.biggestVsSmallestText
    }
    if (this.hasModeTarget) {
      // Biggest vs Smallest allows both solo and team — no lock, no forced value.
      this.modeTarget.classList.remove("opacity-60", "pointer-events-none")
      if (this._priorMode) {
        this.modeTarget.value = this._priorMode
        this._priorMode = null
      }
    }
    if (this.hasModeNoteTarget) this.modeNoteTarget.classList.add("hidden")

    if (this.hasSlotsHeadingTarget) this.slotsHeadingTarget.textContent = "Species configuration"
    if (this.hasSlotsHelpTarget) {
      this.slotsHelpTarget.textContent = "Pick the one species this tournament covers. The slot count is ignored — every entry keeps their biggest and smallest fish."
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

    if (this.hasTrainBuilderTarget) this.trainBuilderTarget.classList.add("hidden")
  }

  // Progressive Length's form UI is Biggest vs Smallest's: solo-or-team unlocked,
  // exactly one species row, slot count ignored, no train builder. Delegate and
  // override only the two strings that differ — the same way _applySmallestFish
  // delegates to _applyStandard.
  _applyProgressiveLength() {
    this._applyBiggestVsSmallest()
    if (this.hasFormatDescriptionTarget) {
      this.formatDescriptionTarget.textContent = this.formatDescriptionTarget.dataset.progressiveLengthText
    }
    if (this.hasSlotsHelpTarget) {
      this.slotsHelpTarget.textContent = "Pick the one species this tournament covers. The slot count is ignored — the ladder is unbounded."
    }
  }

  // Beat the Average's slot behavior is Standard's: multi-species rows,
  // slot count meaningless but harmless. Delegate and override the
  // description/help copy, then force + lock the blind checkbox since this
  // format is always blind during play (enforced server-side too).
  _applyBeatTheAverage() {
    this._applyStandard()
    if (this.hasFormatDescriptionTarget) {
      this.formatDescriptionTarget.textContent = this.formatDescriptionTarget.dataset.beatTheAverageText
    }
    if (this.hasSlotsHelpTarget) {
      this.slotsHelpTarget.textContent = "Pick one or more species. Every catch counts toward one combined average; the slot count is ignored."
    }
    // Beat the Average is always blind — force the checkbox on and lock it.
    // Capture the pre-forced checked value so _restoreBlindCheckbox() can put
    // it back when the user switches to another format; guard the capture so
    // a re-entrant sync() while already forced doesn't overwrite it with `true`.
    if (this.hasBlindCheckboxTarget && !this.blindCheckboxTarget.disabled) {
      if (!this._blindForced) this._blindPriorChecked = this.blindCheckboxTarget.checked
      this.blindCheckboxTarget.checked = true
      this.blindCheckboxTarget.classList.add("opacity-60", "pointer-events-none")
      this._blindForced = true
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

    if (this.hasTrainBuilderTarget) this.trainBuilderTarget.classList.add("hidden")
  }

  _applySmallestFish() {
    this._applyStandard()
    if (this.hasFormatDescriptionTarget) {
      this.formatDescriptionTarget.textContent = this.formatDescriptionTarget.dataset.smallestFishText
    }
  }

  _applyProWalleye() {
    if (this.hasFormatDescriptionTarget) {
      this.formatDescriptionTarget.textContent = this.formatDescriptionTarget.dataset.proWalleyeText
    }
    if (this.hasModeTarget) {
      // Pro Walleye allows solo or team — unlock and restore prior selection.
      this.modeTarget.classList.remove("opacity-60", "pointer-events-none")
      if (this._priorMode) {
        this.modeTarget.value = this._priorMode
        this._priorMode = null
      }
    }
    if (this.hasModeNoteTarget) this.modeNoteTarget.classList.add("hidden")

    if (this.hasSlotsHeadingTarget) this.slotsHeadingTarget.textContent = "Species configuration"
    if (this.hasSlotsHelpTarget) {
      this.slotsHelpTarget.textContent = "Locked to Walleye. Five-fish basket, at most 2 fish over 55 cm; the slot count is ignored."
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

    if (this.hasTrainBuilderTarget) this.trainBuilderTarget.classList.add("hidden")
  }

  _applyBingo() {
    if (this.hasFormatDescriptionTarget) {
      this.formatDescriptionTarget.textContent = this.formatDescriptionTarget.dataset.bingoText
    }
    if (this.hasModeNoteTarget) this.modeNoteTarget.classList.add("hidden")
    // Bingo needs no scoring slots or train — hide the whole slots section.
    if (this.hasSlotsSectionTarget) this.slotsSectionTarget.classList.add("hidden")
    if (this.hasTrainBuilderTarget) this.trainBuilderTarget.classList.add("hidden")
  }

  // Undoes the force-checked + locked state Beat the Average applies to the
  // blind checkbox, restoring whatever the checkbox was set to before it was
  // forced (not just unlocking) — so the forced-on value doesn't linger onto
  // another format, e.g. Bingo, whose bingo_not_blind validation forbids
  // blind_leaderboard = true.
  _restoreBlindCheckbox() {
    if (!this.hasBlindCheckboxTarget || !this._blindForced) return
    this.blindCheckboxTarget.checked = this._blindPriorChecked ?? false
    this.blindCheckboxTarget.classList.remove("opacity-60", "pointer-events-none")
    this._blindForced = false
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
