import { Controller } from "@hotwired/stimulus"
import { enqueueCatch } from "offline/db"

export default class extends Controller {
  static targets = ["speciesSelect", "lengthInput", "submitButton", "status"]
  static values = { csrfToken: String }

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
    if (!this.photoBlob)                 return "Take a photo first."
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
    window.location.href = "/?queued=1"
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
