import { Controller } from "@hotwired/stimulus"
import { enqueueCatch } from "offline/db"
import { convertLength, snapToGrid } from "lib/length_convert"

export default class extends Controller {
  static targets = ["speciesSelect", "lengthInput", "lengthLabel", "noteInput", "submitButton", "status", "tagWrapper", "tagInput", "weightInput"]
  static values = { csrfToken: String, capsBySpeciesId: Object, teammateUserId: String, taggedSpeciesId: String, videoRequired: Boolean }

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
    if (this.hasVideoRequiredValue && this.videoRequiredValue && !this.videoBlob && !this.videoFailed) {
      return "Record the release video, or tap “Mark video failed”."
    }
    return null
  }

  async submit(event) {
    event.preventDefault()
    const missing = this._missingFieldMessage()
    if (missing) { this.statusTarget.textContent = missing; return }

    this._setSubmitting(true)
    try {
      // Read the photo bytes NOW, while the angler is still holding the fish
      // and can retake the shot. WebKit stores IndexedDB blobs as file
      // references that can become unreadable later — by drain time the fish
      // is released and the photo is unrecoverable. Storing the bytes inline
      // (ArrayBuffer, not Blob) sidesteps that failure mode entirely.
      const photo = await this._packBlob(this.photoBlob, "photo.jpg")
      if (!photo) {
        this._setSubmitting(false)
        this.statusTarget.textContent = "That photo couldn't be read — retake it and submit again."
        return
      }
      // Video is optional: an unreadable one is dropped rather than blocking the catch.
      const video = this.videoBlob ? await this._packBlob(this.videoBlob, "video") : null

      const position = await this.tryGeolocate()
      const record = {
        client_uuid: this.clientUuid,
        species_id: this.speciesSelectTarget.value,
        length_inches: this._toInches(this.lengthInputTarget.value),
        length_unit: this.lengthInputTarget.dataset.catchFormUnit,
        captured_at_device: new Date().toISOString(),
        captured_at_gps: position?.gpsTime ?? null,
        latitude: position?.coords?.latitude ?? null,
        longitude: position?.coords?.longitude ?? null,
        gps_accuracy_m: position?.coords?.accuracy ?? null,
        app_build: document.documentElement.dataset.appBuild,
        note: this.noteInputTarget.value,
        tag_number: (this.hasTagInputTarget ? this.tagInputTarget.value : "").trim().toUpperCase() || null,
        weight_text: (this.hasWeightInputTarget ? this.weightInputTarget.value : "").trim() || null,
        photo: photo,
        video: video,
        video_failed: this.videoFailed,
        teammate_user_id: this.teammateUserIdValue || null
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

  // Packs a Blob/File into { bytes, type, name, size } for inline IndexedDB
  // storage. Returns null when the blob is missing, unreadable, or empty —
  // the same three cases offline/blob.js#materialize refuses to upload.
  async _packBlob(blob, fallbackName) {
    if (!blob) return null
    try {
      const bytes = await blob.arrayBuffer()
      if (!bytes || bytes.byteLength === 0) return null
      return { bytes: bytes, type: blob.type || "image/jpeg", name: blob.name || fallbackName, size: bytes.byteLength }
    } catch (_) {
      return null
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
