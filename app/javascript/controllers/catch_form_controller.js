import { Controller } from "@hotwired/stimulus"
import { enqueueCatch } from "offline/db"

export default class extends Controller {
  static targets = ["speciesSelect", "lengthInput", "lengthLabel", "noteInput", "submitButton", "status"]
  static values = { csrfToken: String, capsBySpeciesId: Object }

  connect() {
    this.photoBlob = null
    this.videoBlob = null
    this.videoFailed = false
    this.refresh()
  }

  onPhotoCaptured(event) { this.photoBlob = event.detail.blob; this.refresh() }
  onVideoCaptured(event) { this.videoBlob = event.detail.blob; this.videoFailed = false; this.refresh() }
  onVideoFailed()        { this.videoBlob = null; this.videoFailed = true; this.refresh() }

  refresh() {
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
    if (!this.photoBlob) return "Take a photo first."
    return null
  }

  async submit(event) {
    event.preventDefault()
    const missing = this._missingFieldMessage()
    if (missing) { this.statusTarget.textContent = missing; return }

    const position = await this.tryGeolocate()
    const record = {
      client_uuid: crypto.randomUUID(),
      species_id: this.speciesSelectTarget.value,
      length_inches: this._toInches(this.lengthInputTarget.value),
      captured_at_device: new Date().toISOString(),
      captured_at_gps: position?.gpsTime ?? null,
      latitude: position?.coords?.latitude ?? null,
      longitude: position?.coords?.longitude ?? null,
      gps_accuracy_m: position?.coords?.accuracy ?? null,
      app_build: document.documentElement.dataset.appBuild,
      note: this.noteInputTarget.value,
      photo: this.photoBlob,
      video: this.videoBlob,
      video_failed: this.videoFailed
    }

    await enqueueCatch(record)

    if ("serviceWorker" in navigator && "SyncManager" in window) {
      try {
        const reg = await navigator.serviceWorker.ready
        await reg.sync.register("catch-sync")
      } catch (_) {}
    }

    window.dispatchEvent(new Event("bsfamilies:try-sync"))
    window.location.href = "/"
  }

  setUnit(event) {
    const newUnit = event.target.value
    const oldUnit = this.lengthInputTarget.dataset.catchFormUnit
    if (oldUnit === newUnit) return

    const v = parseFloat(this.lengthInputTarget.value)
    if (!Number.isNaN(v)) {
      const factor = oldUnit === "inches" && newUnit === "centimeters" ? 2.54
                   : oldUnit === "centimeters" && newUnit === "inches" ? 1 / 2.54
                   : 1
      this.lengthInputTarget.value = (v * factor).toFixed(2)
    }

    this.lengthInputTarget.dataset.catchFormUnit = newUnit
    this.lengthInputTarget.step = newUnit === "centimeters" ? "0.5" : "0.25"
    if (this.hasLengthLabelTarget) {
      this.lengthLabelTarget.textContent = newUnit === "centimeters" ? "Length (cm)" : "Length (in)"
    }

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

  _toInches(rawValue) {
    const v = parseFloat(rawValue)
    if (Number.isNaN(v)) return rawValue
    const unit = this.lengthInputTarget.dataset.catchFormUnit
    return unit === "centimeters" ? (v / 2.54).toFixed(2) : v.toFixed(2)
  }

  async tryGeolocate() {
    if (!navigator.geolocation) return null
    return new Promise((resolve) => {
      navigator.geolocation.getCurrentPosition(
        (pos) => resolve({ coords: pos.coords, gpsTime: new Date(pos.timestamp).toISOString() }),
        () => resolve(null),
        { enableHighAccuracy: true, timeout: 8000, maximumAge: 0 }
      )
    })
  }
}
