import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["car", "carContainer", "carTemplate", "addButton", "carCount"]
  static values = { min: { type: Number, default: 3 }, max: { type: Number, default: 6 } }

  connect() {
    this._refresh()
  }

  add(event) {
    event.preventDefault()
    if (this.carTargets.length >= this.maxValue) return
    const fragment = this.carTemplateTarget.content.cloneNode(true)
    this.carContainerTarget.appendChild(fragment)
    this._refresh()
  }

  remove(event) {
    event.preventDefault()
    if (this.carTargets.length <= this.minValue) return
    const car = event.currentTarget.closest("[data-fish-train-builder-target='car']")
    if (car) car.remove()
    this._refresh()
  }

  moveUp(event) {
    event.preventDefault()
    const car = event.currentTarget.closest("[data-fish-train-builder-target='car']")
    const prev = car?.previousElementSibling
    if (car && prev) car.parentNode.insertBefore(car, prev)
    this._refresh()
  }

  moveDown(event) {
    event.preventDefault()
    const car = event.currentTarget.closest("[data-fish-train-builder-target='car']")
    const next = car?.nextElementSibling
    if (car && next) car.parentNode.insertBefore(next, car)
    this._refresh()
  }

  _refresh() {
    const cars = this.carTargets
    if (this.hasCarCountTarget) {
      this.carCountTarget.textContent = `${cars.length} / ${this.maxValue} cars`
    }
    if (this.hasAddButtonTarget) {
      this.addButtonTarget.disabled = cars.length >= this.maxValue
    }
    cars.forEach((car, i) => {
      const upBtn     = car.querySelector("[data-action*='fish-train-builder#moveUp']")
      const downBtn   = car.querySelector("[data-action*='fish-train-builder#moveDown']")
      const removeBtn = car.querySelector("[data-action*='fish-train-builder#remove']")
      if (upBtn)     upBtn.disabled     = i === 0
      if (downBtn)   downBtn.disabled   = i === cars.length - 1
      if (removeBtn) removeBtn.disabled = cars.length <= this.minValue
    })
  }
}
