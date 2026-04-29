import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "image"]

  open(event) {
    const trigger = event.currentTarget
    const src = trigger.dataset.lightboxSrc
    if (!src) return
    this.imageTarget.src = src
    this.imageTarget.alt = trigger.dataset.lightboxAlt || ""
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
    this.imageTarget.removeAttribute("src")
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
