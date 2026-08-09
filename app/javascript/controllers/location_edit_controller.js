import { Controller } from "@hotwired/stimulus"
import L from "leaflet"
import { configureDefaultIcons } from "lib/leaflet_default_icons"

// Admin-only catch GPS editor: a draggable marker whose position is mirrored into
// hidden lat/lng fields submitted to correct_location.
export default class extends Controller {
  static values = { lat: Number, lng: Number, hasPoint: Boolean }
  static targets = ["map", "lat", "lng", "readout"]

  connect() {
    configureDefaultIcons()
    this.initMap()
    // This page (judges/catches/show) renders under the application layout and
    // Judges::BaseController never calls disable_turbo_snapshot_cache!, so an
    // edge-swipe back is a restoration visit whose snapshot was captured with
    // the map panes still live — disconnect() runs too late to clean it. Today
    // the restored container keeps its _leaflet_id and connect() no-ops rather
    // than stacking a second map, but that is Turbo's behaviour to change, not
    // ours to rely on. Tear down before capture so the snapshot is clean either
    // way, matching map_controller.
    this.boundBeforeCache = () => this.teardown()
    document.addEventListener("turbo:before-cache", this.boundBeforeCache)
  }

  initMap() {
    const start = [this.latValue, this.lngValue]
    const map = L.map(this.mapTarget).setView(start, this.hasPointValue ? 13 : 7)
    this.map = map
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

  // Tear the map down so its tile layer and click/dragend listeners don't leak,
  // and so a Turbo Drive restore that reuses this element doesn't hit Leaflet's
  // "Map container is already initialized" guard on the next connect().
  disconnect() {
    document.removeEventListener("turbo:before-cache", this.boundBeforeCache)
    this.teardown()
  }

  teardown() {
    if (this.map) {
      this.map.remove()
      this.map = null
      this.marker = null
    }
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
