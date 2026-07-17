import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "video", "recordButton", "stopButton", "failedButton"]

  async start() {
    // A getUserMedia rejection (permission denied, no camera) must route
    // through markFailed like every other failure — an uncaught throw here
    // wedges the video UI and the catch form never hears the failed event.
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: "environment",
          width: { ideal: 1920 },
          height: { ideal: 1080 }
        },
        audio: true
      })
      this.videoTarget.srcObject = this.stream
      await this.videoTarget.play()
    } catch (_) {
      this.markFailed()
      return
    }
    this.chunks = []
    // iOS Safari only supports video/mp4 for MediaRecorder; Chrome/Firefox prefer webm.
    // Hardcoding webm previously made every iPhone hit NotSupportedError on construct.
    // A browser missing MediaRecorder entirely must fail gracefully, not throw a
    // ReferenceError that skips the failed-event the catch form listens for.
    if (typeof MediaRecorder === "undefined" || !MediaRecorder.isTypeSupported) {
      this.markFailed()
      return
    }
    const candidates = ["video/mp4;codecs=h264,aac", "video/mp4", "video/webm;codecs=vp9", "video/webm"]
    const mimeType = candidates.find((t) => MediaRecorder.isTypeSupported(t))
    if (!mimeType) {
      this.markFailed()
      return
    }
    this.recorder = new MediaRecorder(this.stream, { mimeType })
    this.recorder.ondataavailable = (e) => { if (e.data.size) this.chunks.push(e.data) }
    this.recorder.onstop = () => {
      this.blob = new Blob(this.chunks, { type: mimeType })
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
