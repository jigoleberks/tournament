module Catches
  # Detects whether a catch photo carries the fingerprint of a screen capture
  # rather than a genuine camera capture. Soft posture: this only surfaces a
  # flag for judge review, never blocks.
  #
  # Signal: progressive JPEG encoding. Phone cameras and the iOS HEIC->JPEG
  # transcode both emit *baseline* JPEGs; the screenshot -> JPEG pipeline
  # (Firefox / the Android screenshot tool) emits *progressive* JPEGs. Across the
  # full catch corpus this cleanly separated the known screenshots from every
  # camera photo (2/2 hits, 0 false positives), and unlike a resolution rule it
  # is independent of image size, so a high-resolution screenshot is still caught.
  #
  # Limits: this fingerprints the *encoder*, not the semantics — a screenshot
  # re-encoded baseline before upload would evade it, and a future legit photo
  # path that emits progressive JPEGs would false-positive. Re-verify the
  # fingerprint if members' capture habits change.
  class ScreenshotSignature
    def self.call(catch_record)
      return false unless catch_record.photo.attached?

      image = ::Vips::Image.new_from_buffer(catch_record.photo.download, "")
      image.get_typeof("jpeg-multiscan") != 0 && image.get("jpeg-multiscan").to_i == 1
    rescue ::StandardError
      false
    end
  end
end
