import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.handler = () => this.show()
    window.addEventListener("bsfamilies:catch-synced", this.handler)
  }

  disconnect() {
    window.removeEventListener("bsfamilies:catch-synced", this.handler)
  }

  show() {
    clearTimeout(this.hideTimeout)
    this.element.classList.remove("hidden", "opacity-0")
    this.element.classList.add("opacity-100")
    this.hideTimeout = setTimeout(() => {
      this.element.classList.remove("opacity-100")
      this.element.classList.add("opacity-0")
      setTimeout(() => this.element.classList.add("hidden"), 300)
    }, 4000)
  }
}
