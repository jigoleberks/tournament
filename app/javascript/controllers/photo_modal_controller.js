import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // iOS chains touch scrolls through short overlays into the page behind:
    // "scrolling the photo" scrolled the leaderboard underneath, so closing
    // the modal landed the user somewhere else. Lock body scroll while open.
    document.body.classList.add("overflow-hidden")
  }

  disconnect() {
    document.body.classList.remove("overflow-hidden")
  }

  close() {
    this.element.closest("turbo-frame").innerHTML = ""
  }
}
