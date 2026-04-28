import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "video", "recordButton", "stopButton", "failedButton"]

  async start() {
    this.stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: "environment" },
      audio: true
    })
    this.videoTarget.srcObject = this.stream
    await this.videoTarget.play()
    this.chunks = []
    this.recorder = new MediaRecorder(this.stream, { mimeType: "video/webm" })
    this.recorder.ondataavailable = (e) => { if (e.data.size) this.chunks.push(e.data) }
    this.recorder.onstop = () => {
      this.blob = new Blob(this.chunks, { type: "video/webm" })
      this.previewTarget.src = URL.createObjectURL(this.blob)
      this.previewTarget.dataset.captured = "true"
      this.dispatch("captured", { detail: { blob: this.blob } })
      this.stopStream()
    }
    this.recorder.start()
  }

  stop() {
    if (this.recorder && this.recorder.state !== "inactive") this.recorder.stop()
  }

  markFailed() {
    this.blob = null
    this.previewTarget.dataset.captured = "failed"
    this.dispatch("failed")
    this.stopStream()
  }

  stopStream() {
    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop())
      this.stream = null
    }
  }

  disconnect() { this.stop(); this.stopStream() }
}
