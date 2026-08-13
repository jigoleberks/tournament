import { Controller } from "@hotwired/stimulus"
import { iosBrowserTab } from "lib/ios_device"

// Reveals the home-screen install walkthrough in an iOS browser tab. Detection
// is shared with push_register_controller so the banner and the push toggle's
// "available after install" hint agree — the old server-side UA match missed
// iPads that report a Macintosh UA (iPadOS 13+).
export default class extends Controller {
  connect() {
    this.element.hidden = !iosBrowserTab()
  }
}
