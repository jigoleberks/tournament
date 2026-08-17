import { Controller } from "@hotwired/stimulus"

// Behaviour for the league-night scheduler's two columns.
//
// Four jobs, all advisory or cosmetic — nothing here changes what the server
// accepts:
//   1. Hide the slot-count field for formats whose count the model pins
//      (pro_walleye forces 5, progressive_length forces 1).
//   2. Reveal the target-range fields for Random Bag, the only offered format
//      needing anything beyond a species. They ship with Tailwind's `hidden`
//      on them, so this controller is the ONLY thing that ever un-hides them.
//   3. Lock Side's blind checkbox on for formats that force blind themselves
//      (beat_the_average, random_bag), so it doesn't pretend to be a choice.
//   4. Warn when Side is visible while both columns score the same species.
//      Main is always blind, so a visible Side leaderboard is a side channel
//      into it. Whether that matters is the organizer's call, so this never
//      blocks submission.
//
// Every target is read through its `has…Target` guard: a half-scheduled night
// renders only the ONE column still missing, so on that screen either the
// `main*` targets or the `side*` ones (and `leakWarning` with them) are simply
// absent. A bare `this.mainFormatTarget` there raises on connect and takes the
// whole controller down with it — which would leave the range rows stuck
// hidden, since nothing else removes that class.
const FIXED_COUNT_FORMATS = ["pro_walleye", "progressive_length"]
const FORCED_BLIND_FORMATS = ["beat_the_average", "random_bag"]
const RANGE_FORMATS = ["random_bag"]

export default class extends Controller {
  static targets = [
    "mainFormat", "mainSpecies", "mainCountRow", "mainRangeRow",
    "sideFormat", "sideSpecies", "sideCountRow", "sideRangeRow", "sideBlind",
    "leakWarning"
  ]

  connect() { this.sync() }

  sync() {
    this._syncColumn(this.hasMainFormatTarget && this.mainFormatTarget,
                     this.hasMainCountRowTarget && this.mainCountRowTarget,
                     this.hasMainRangeRowTarget && this.mainRangeRowTarget)
    this._syncColumn(this.hasSideFormatTarget && this.sideFormatTarget,
                     this.hasSideCountRowTarget && this.sideCountRowTarget,
                     this.hasSideRangeRowTarget && this.sideRangeRowTarget)
    // Before the leak warning: a forced-blind Side is not a leak, and the
    // warning reads the checkbox this method may have just ticked.
    this._syncForcedBlind()
    this._syncLeakWarning()
  }

  _syncColumn(formatTarget, countRow, rangeRow) {
    if (!formatTarget) return
    const format = formatTarget.value
    if (countRow) countRow.classList.toggle("hidden", FIXED_COUNT_FORMATS.includes(format))
    if (rangeRow) rangeRow.classList.toggle("hidden", !RANGE_FORMATS.includes(format))
  }

  // Forcing the box on is only half the job: switching BACK has to restore what
  // the operator (or the Side template, which may well be blind) had set, not
  // clear it. Task 5 gave the checkbox a companion hidden field so it can
  // submit "off", which means a blanket un-tick here would silently turn off a
  // template-blind Side the moment a forced-blind format was passed through.
  //
  // The checkbox really is `disabled` while forced, so it submits nothing and
  // the hidden field's "0" is what arrives. That is fine: Tournament's
  // force_beat_the_average_blind / force_random_bag_blind set the flag back on
  // before validation regardless of what was posted.
  _syncForcedBlind() {
    if (!this.hasSideBlindTarget || !this.hasSideFormatTarget) return
    const box = this.sideBlindTarget
    const forced = FORCED_BLIND_FORMATS.includes(this.sideFormatTarget.value)

    if (forced) {
      // Captured on the way IN only — a later sync while still forced would
      // otherwise record the forced `true` as the operator's own answer.
      if (!this._blindForced) this._blindPriorChecked = box.checked
      box.checked = true
      box.disabled = true
      this._blindForced = true
    } else if (this._blindForced) {
      box.disabled = false
      box.checked = this._blindPriorChecked
      this._blindForced = false
    }
  }

  _syncLeakWarning() {
    if (!this.hasLeakWarningTarget) return
    if (!this.hasMainSpeciesTarget || !this.hasSideSpeciesTarget || !this.hasSideBlindTarget) return

    const species = this.sideSpeciesTarget.value
    const sameSpecies = species !== "" && species === this.mainSpeciesTarget.value
    const sideVisible = !this.sideBlindTarget.checked

    if (sameSpecies && sideVisible) {
      const label = this.sideSpeciesTarget.selectedOptions[0]?.text ?? "the same species"
      this.leakWarningTarget.textContent =
        `Both nights score ${label} and the main tournament is blind — a visible side leaderboard reveals its standings.`
      this.leakWarningTarget.classList.remove("hidden")
    } else {
      this.leakWarningTarget.classList.add("hidden")
    }
  }
}
