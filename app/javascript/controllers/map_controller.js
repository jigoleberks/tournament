import { Controller } from "@hotwired/stimulus"
import L from "leaflet"
import { configureDefaultIcons } from "lib/leaflet_default_icons"

export default class extends Controller {
  static values = {
    points: Array
  }

  connect() {
    configureDefaultIcons()
    this.initMap()
    // disconnect() alone can't protect a Turbo Drive restore: it runs after
    // Turbo has already captured the page snapshot, so the cached copy would
    // still hold the fully rendered panes (the clone loses the _leaflet_id
    // expando, so the next connect() happily builds a second map on top —
    // doubled markers, broken hit testing). turbo:before-cache fires before
    // capture; tearing down there is what makes the snapshot clean.
    this.boundBeforeCache = () => this.teardown()
    document.addEventListener("turbo:before-cache", this.boundBeforeCache)
  }

  initMap() {
    const mapElement = this.element
    const points = this.pointsValue.filter(p => p.lat && p.lng)

    if (points.length === 0) {
      mapElement.innerHTML = '<div class="flex items-center justify-center h-full text-slate-400 italic">No GPS data for these catches.</div>'
      return
    }

    const map = L.map(mapElement).setView([points[0].lat, points[0].lng], 13)
    this.map = map

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(map)

    const markers = []
    points.forEach(p => {
      const marker = L.marker([p.lat, p.lng]).addTo(map)
      if (p.popup) {
        marker.bindPopup(p.popup)
      }
      markers.push(marker)
    })

    if (markers.length > 0) {
      const group = new L.featureGroup(markers)
      map.fitBounds(group.getBounds().pad(0.1))
    }
  }

  // Tear the map down so its tile layer and listeners don't leak.
  // (location_edit_controller gets away with disconnect-only teardown because
  // the admin layout is turbo-cache-control no-cache — no snapshot restores.)
  disconnect() {
    document.removeEventListener("turbo:before-cache", this.boundBeforeCache)
    this.teardown()
  }

  teardown() {
    if (this.map) {
      this.map.remove()
      this.map = null
      // Leave nothing for the snapshot: connect() rebuilds from pointsValue,
      // including the "No GPS data" empty state.
      this.element.innerHTML = ""
    }
  }
}
