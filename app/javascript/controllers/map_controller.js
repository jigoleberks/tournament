import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

export default class extends Controller {
  static values = {
    points: Array
  }

  connect() {
    this.initMap()
  }

  initMap() {
    const mapElement = this.element
    const points = this.pointsValue.filter(p => p.lat && p.lng)

    if (points.length === 0) {
      mapElement.innerHTML = '<div class="flex items-center justify-center h-full text-slate-400 italic">No GPS data for these catches.</div>'
      return
    }

    const map = L.map(mapElement).setView([points[0].lat, points[0].lng], 13)

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
}
