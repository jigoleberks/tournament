import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "input", "video", "captureButton", "retakeButton"]

  async start() {
    this.stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: "environment" },
      audio: false
    })
    this.videoTarget.srcObject = this.stream
    await this.videoTarget.play()
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
      this.stop()
    }, "image/jpeg", 0.9)
  }

  retake() {
    this.previewTarget.removeAttribute("src")
    this.previewTarget.dataset.captured = "false"
    this.input = null
    this.start()
  }

  stop() {
    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop())
      this.stream = null
    }
  }

  disconnect() { this.stop() }

  get blob() { return this.input }
}
