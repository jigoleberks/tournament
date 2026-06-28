import { Controller } from "@hotwired/stimulus"

// Native-camera photo capture. Tapping "Take photo" opens the phone's built-in
// camera through a file input with capture="environment", which returns a
// full-resolution still on BOTH iOS and Android. (getUserMedia video frames —
// the previous approach — are capped well below sensor resolution on every
// phone.) The OS camera owns the viewfinder and zoom; this controller just
// surfaces the captured File and emits the same "captured" event the previous
// implementation did, so catch_form_controller is unchanged.
//
// State: "idle" (no photo yet) / "captured" (a file chosen, preview shown).
export default class extends Controller {
  static targets = ["input", "preview", "openButton", "retakeButton"]

  connect() {
    this.capturedFile = null
    this._setState("idle")
  }

  // "Take photo" / "Retake" open the native camera.
  open() {
    this.inputTarget.click()
  }

  retake() {
    // Clearing value guarantees a change event fires even if the user re-picks
    // the same file the OS would otherwise treat as no-change.
    this.inputTarget.value = ""
    this.inputTarget.click()
  }

  onChange() {
    const file = this.inputTarget.files && this.inputTarget.files[0]
    if (!file) return   // user backed out of the camera — keep prior state
    this.capturedFile = file
    if (this.previewTarget.src) URL.revokeObjectURL(this.previewTarget.src)
    this.previewTarget.src = URL.createObjectURL(file)
    this.previewTarget.dataset.captured = "true"
    this.dispatch("captured", { detail: { blob: file } })
    this._setState("captured")
  }

  // Preserved for parity with the old controller / any external reader.
  get blob() { return this.capturedFile }

  disconnect() {
    if (this.hasPreviewTarget && this.previewTarget.src) {
      URL.revokeObjectURL(this.previewTarget.src)
    }
  }

  _setState(state) {
    this.state = state
    this._toggle(this.openButtonTarget,   state !== "captured")
    this._toggle(this.previewTarget,      state === "captured")
    this._toggle(this.retakeButtonTarget, state === "captured")
  }

  _toggle(el, visible) {
    if (el) el.classList.toggle("hidden", !visible)
  }
}
