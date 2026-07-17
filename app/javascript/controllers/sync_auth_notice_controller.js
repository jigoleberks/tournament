import { Controller } from "@hotwired/stimulus"

// Reveals the "sign in to upload your saved catches" notice when a queue
// drain hits a 401 (offline/sync.js leaves the catches queued and dispatches
// bsfamilies:sync-auth-required). Rendered hidden in the application layout,
// so the notice works both mid-session (cookie expired under the user) and on
// the sign-in page itself (the load-drain 401s before the user signs in).
export default class extends Controller {
  connect() {
    this.boundShow = () => { this.element.hidden = false }
    window.addEventListener("bsfamilies:sync-auth-required", this.boundShow)
  }

  disconnect() {
    window.removeEventListener("bsfamilies:sync-auth-required", this.boundShow)
  }
}
