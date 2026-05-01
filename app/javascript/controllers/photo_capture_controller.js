import { Controller } from "@hotwired/stimulus"

// State: "idle" (no camera, no capture), "streaming" (camera open),
// "captured" (photo taken, camera stopped, preview shown).
export default class extends Controller {
  static targets = [
    "preview", "video", "openButton", "captureButton", "retakeButton",
    "fullscreenButton", "fullscreenContainer", "fullscreenSlot", "inlineSlot"
  ]

  async connect() {
    this._setState("idle")
    try {
      await this.start()
    } catch (err) {
      // Permission denied, no camera, or insecure context — fall back to the
      // Open camera button so the user can retry with an explicit gesture.
      console.warn("Camera auto-start failed:", err)
    }
  }

  async start() {
    this.stream = await navigator.mediaDevices.getUserMedia({
      video: {
        facingMode: "environment",
        width: { ideal: 4032 },
        height: { ideal: 3024 }
      },
      audio: false
    })
    this.videoTarget.srcObject = this.stream
    await this.videoTarget.play()
    this._setState("streaming")
  }

  capture() {
    const v = this.videoTarget
    const canvas = document.createElement("canvas")
    canvas.width = v.videoWidth
    canvas.height = v.videoHeight
    canvas.getContext("2d").drawImage(v, 0, 0)
    canvas.toBlob((blob) => {
      this.previewTarget.src = URL.createObjectURL(blob)
      this.previewTarget.dataset.captured = "true"
      this.input = blob
      this.dispatch("captured", { detail: { blob } })
      if (this._isFullscreen()) this._collapseFullscreen()
      this.stop()
      this._setState("captured")
    }, "image/jpeg", 0.9)
  }

  retake() {
    this.previewTarget.removeAttribute("src")
    this.previewTarget.dataset.captured = "false"
    this.input = null
    this.start()
  }

  enterFullscreen() {
    if (!this.stream || !this.hasFullscreenContainerTarget) return
    this.fullscreenSlotTarget.appendChild(this.videoTarget)
    this.videoTarget.classList.remove("aspect-[3/4]", "rounded-lg")
    this.videoTarget.classList.add("w-full", "h-full")
    this.fullscreenContainerTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  exitFullscreen() {
    this._collapseFullscreen()
  }

  stop() {
    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop())
      this.stream = null
    }
  }

  disconnect() {
    if (this._isFullscreen()) this._collapseFullscreen()
    this.stop()
  }

  get blob() { return this.input }

  _setState(state) {
    this.state = state
    this._toggle(this.openButtonTarget,       state === "idle")
    this._toggle(this.videoTarget,            state === "streaming")
    this._toggle(this.captureButtonTarget,    state === "streaming")
    this._toggle(this.fullscreenButtonTarget, state === "streaming")
    this._toggle(this.previewTarget,          state === "captured")
    this._toggle(this.retakeButtonTarget,     state === "captured")
  }

  _toggle(el, visible) {
    if (!el) return
    el.classList.toggle("hidden", !visible)
  }

  _isFullscreen() {
    return this.hasFullscreenContainerTarget &&
           !this.fullscreenContainerTarget.classList.contains("hidden")
  }

  _collapseFullscreen() {
    if (!this.hasFullscreenContainerTarget) return
    this.inlineSlotTarget.appendChild(this.videoTarget)
    this.videoTarget.classList.remove("w-full", "h-full")
    this.videoTarget.classList.add("aspect-[3/4]", "rounded-lg")
    this.fullscreenContainerTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }
}
