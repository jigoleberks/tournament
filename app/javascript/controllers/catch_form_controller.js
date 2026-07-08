import { Controller } from "@hotwired/stimulus"
import { enqueueCatch } from "offline/db"
import { convertLength, snapToGrid } from "lib/length_convert"

export default class extends Controller {
  static targets = ["speciesSelect", "lengthInput", "lengthLabel", "noteInput", "submitButton", "status", "tagWrapper", "tagInput", "weightInput",
                    "step1", "step2", "baitSelect", "waterDepthInput", "waterTempInput", "structureSelect"]
  static values = { csrfToken: String, capsBySpeciesId: Object, teammateUserId: String, taggedSpeciesId: String }

  connect() {
    this.photoBlob = null
    this.videoBlob = null
    this.videoFailed = false
    this.clientUuid = crypto.randomUUID()
    this._restoreUnitFromStorage()
    this.refresh()
  }

  _restoreUnitFromStorage() {
    let stored
    try { stored = localStorage.getItem("catchLengthUnit") } catch (_) { return }
    if (!stored) return
    if (!["inches", "centimeters"].includes(stored)) return
    const current = this.lengthInputTarget.dataset.catchFormUnit
    if (stored === current) return
    const radio = this.element.querySelector(`input[name="length_unit_toggle"][value="${stored}"]`)
    if (!radio) return
    radio.checked = true
    this.setUnit({ target: radio })
  }

  onPhotoCaptured(event) { this.photoBlob = event.detail.blob; this.refresh() }
  onVideoCaptured(event) { this.videoBlob = event.detail.blob; this.videoFailed = false; this.refresh() }
  onVideoFailed()        { this.videoBlob = null; this.videoFailed = true; this.refresh() }

  refresh() {
    const isTagged = this.hasTaggedSpeciesIdValue
                  && this.taggedSpeciesIdValue !== ""
                  && String(this.speciesSelectTarget.value) === String(this.taggedSpeciesIdValue)
    if (this.hasTagWrapperTarget) this.tagWrapperTarget.classList.toggle("hidden", !isTagged)
    this.statusTarget.textContent = this._missingFieldMessage() ?? ""
  }

  _missingFieldMessage() {
    if (!this.speciesSelectTarget.value) return "Pick a species."
    if (!this.lengthInputTarget.value)   return "Enter the length."
    const cap = this.capsBySpeciesIdValue[this.speciesSelectTarget.value]
    const inches = parseFloat(this._toInches(this.lengthInputTarget.value))
    if (cap && inches > cap) {
      const speciesName = this.speciesSelectTarget.selectedOptions[0]?.text ?? "this species"
      return `${speciesName} can't exceed ${cap}″.`
    }
    const isTagged = this.hasTaggedSpeciesIdValue
                  && this.taggedSpeciesIdValue !== ""
                  && String(this.speciesSelectTarget.value) === String(this.taggedSpeciesIdValue)
    if (isTagged && this.hasTagInputTarget && !this.tagInputTarget.value.trim()) {
      return "Enter the tag number on the fish."
    }
    if (!this.photoBlob) return "Take a photo first."
    return null
  }

  next(event) {
    if (event) event.preventDefault()
    const missing = this._missingFieldMessage()
    if (missing) { this.statusTarget.textContent = missing; return }
    // Stamp the catch *now* (when the fish is being released), not at submit
    // time. The angler may spend minutes on step 2; captured_at_device and the
    // GPS reading should reflect when the photo was taken, not when they hit
    // save. GPS read fires in the background — submit() awaits the promise.
    this.capturedAtDevice = new Date().toISOString()
    this.capturedPositionPromise = this.tryGeolocate()
    if (this.hasStep1Target) this.step1Target.hidden = true
    if (this.hasStep2Target) this.step2Target.hidden = false
    this.statusTarget.textContent = ""
  }

  back(event) {
    if (event) event.preventDefault()
    if (this.hasStep2Target) this.step2Target.hidden = true
    if (this.hasStep1Target) this.step1Target.hidden = false
  }

  async submit(event) {
    event.preventDefault()
    const missing = this._missingFieldMessage()
    if (missing) { this.statusTarget.textContent = missing; return }

    this._setSubmitting(true)
    try {
      // In the two-step flow, next() already stamped captured_at_device and
      // kicked off the GPS read; fall back to fresh values for the single-page
      // flow where neither was stashed.
      const position = this.capturedPositionPromise
        ? await this.capturedPositionPromise
        : await this.tryGeolocate()
      const record = {
        client_uuid: this.clientUuid,
        species_id: this.speciesSelectTarget.value,
        length_inches: this._toInches(this.lengthInputTarget.value),
        length_unit: this.lengthInputTarget.dataset.catchFormUnit,
        captured_at_device: this.capturedAtDevice ?? new Date().toISOString(),
        captured_at_gps: position?.gpsTime ?? null,
        latitude: position?.coords?.latitude ?? null,
        longitude: position?.coords?.longitude ?? null,
        gps_accuracy_m: position?.coords?.accuracy ?? null,
        app_build: document.documentElement.dataset.appBuild,
        note: this.noteInputTarget.value,
        tag_number: (this.hasTagInputTarget ? this.tagInputTarget.value : "").trim().toUpperCase() || null,
        weight_text: (this.hasWeightInputTarget ? this.weightInputTarget.value : "").trim() || null,
        photo: this.photoBlob,
        video: this.videoBlob,
        video_failed: this.videoFailed,
        teammate_user_id: this.teammateUserIdValue || null,
        bait_id: this.hasBaitSelectTarget ? (this.baitSelectTarget.value || null) : null,
        water_depth_feet: this.hasWaterDepthInputTarget ? (this.waterDepthInputTarget.value || null) : null,
        water_temperature_c: this.hasWaterTempInputTarget ? (this.waterTempInputTarget.value || null) : null,
        structure: this.hasStructureSelectTarget ? (this.structureSelectTarget.value || null) : null
      }

      await enqueueCatch(record)

      if ("serviceWorker" in navigator && "SyncManager" in window) {
        try {
          const reg = await navigator.serviceWorker.ready
          await reg.sync.register("catch-sync")
        } catch (_) {}
      }

      // Don't dispatch try-sync here: the upload would race window.location.href below
      // and Safari kills in-flight fetches when a page navigates. The destination page's
      // load handler in offline/sync.js drains the queue on arrival.
      window.location.href = "/"
    } catch (err) {
      this._setSubmitting(false)
      this.statusTarget.textContent = "Couldn't save your catch — try again."
      throw err
    }
  }

  _setSubmitting(flag) {
    if (!this.hasSubmitButtonTarget) return
    const btn = this.submitButtonTarget
    if (flag) {
      btn.disabled = true
      if (btn.dataset.originalLabel == null) btn.dataset.originalLabel = btn.textContent
      btn.textContent = "Submitting…"
    } else {
      btn.disabled = false
      if (btn.dataset.originalLabel) btn.textContent = btn.dataset.originalLabel
    }
  }

  setUnit(event) {
    const newUnit = event.target.value
    const oldUnit = this.lengthInputTarget.dataset.catchFormUnit
    if (oldUnit === newUnit) return

    const v = parseFloat(this.lengthInputTarget.value)
    if (!Number.isNaN(v)) {
      this.lengthInputTarget.value = convertLength(v, oldUnit, newUnit).toFixed(2)
    }

    this.lengthInputTarget.dataset.catchFormUnit = newUnit
    this.lengthInputTarget.step = "0.25"
    if (this.hasLengthLabelTarget) {
      this.lengthLabelTarget.textContent = newUnit === "centimeters" ? "Length (cm)" : "Length (in)"
    }

    try { localStorage.setItem("catchLengthUnit", newUnit) } catch (_) {}

    fetch("/me", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfTokenValue
      },
      body: JSON.stringify({ user: { length_unit: newUnit } })
    }).catch(() => {})

    this.refresh()
  }

  uppercaseTag() {
    if (!this.hasTagInputTarget) return
    this.tagInputTarget.value = this.tagInputTarget.value.toUpperCase()
  }

  _toInches(rawValue) {
    const v = parseFloat(rawValue)
    if (Number.isNaN(v)) return rawValue
    // Snap to the 0.25 grid of the currently selected unit, then convert.
    // This makes the quarter-increment rule real rather than advisory.
    const snapped = snapToGrid(v)
    const unit = this.lengthInputTarget.dataset.catchFormUnit
    return convertLength(snapped, unit, "inches").toFixed(2)
  }

  async tryGeolocate() {
    if (!navigator.geolocation) return null
    return new Promise((resolve) => {
      // Safety timeout: some browsers (notably desktop with no GPS) never fire
      // success or error, leaving submit stuck on "Submitting…" forever.
      const safetyTimeout = setTimeout(() => resolve(null), 10000)
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          clearTimeout(safetyTimeout)
          resolve({ coords: pos.coords, gpsTime: new Date(pos.timestamp).toISOString() })
        },
        () => {
          clearTimeout(safetyTimeout)
          resolve(null)
        },
        { enableHighAccuracy: true, timeout: 8000, maximumAge: 0 }
      )
    })
  }
}
