import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

// Admin-only catch GPS editor: a draggable marker whose position is mirrored into
// hidden lat/lng fields submitted to correct_location.
export default class extends Controller {
  static values = { lat: Number, lng: Number, hasPoint: Boolean }
  static targets = ["map", "lat", "lng", "readout"]

  connect() {
    const start = [this.latValue, this.lngValue]
    const map = L.map(this.mapTarget).setView(start, this.hasPointValue ? 13 : 7)
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(map)

    this.marker = L.marker(start, { draggable: true }).addTo(map)
    this.marker.on("dragend", () => this.sync())
    map.on("click", (e) => { this.marker.setLatLng(e.latlng); this.sync() })
    // Deliberately NOT calling sync() here: the hidden lat/lng fields already hold
    // the catch's real coordinates (or empty for a GPS-less catch) from the server.
    // Syncing on connect would overwrite an empty GPS with the map's centroid
    // fallback, so a no-drag save would write spurious coordinates. We only mirror
    // the marker into the fields once the admin actually moves it.
  }

  sync() {
    const { lat, lng } = this.marker.getLatLng()
    this.latTarget.value = lat.toFixed(6)
    this.lngTarget.value = lng.toFixed(6)
    if (this.hasReadoutTarget) {
      this.readoutTarget.textContent = `Corrected to ${lat.toFixed(5)}, ${lng.toFixed(5)}`
    }
  }
}
