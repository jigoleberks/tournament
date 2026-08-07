import { materialize } from "offline/blob"
import { MAX_VIDEO_BYTES } from "offline/limits"

// Builds the /api/catches FormData for a queued IndexedDB catch record —
// the single source of truth shared by the background drain (offline/sync.js)
// and the manual recovery tool (recover_controller.js). Before this, the
// field list lived in both by copy-paste and every new record field had to be
// added twice; a miss meant the recovery tool silently dropped that field.
//
// `photo` is the already-materialized photo blob (callers materialize it
// first — each handles an unreadable photo differently); `photoName` names
// the upload part.
export async function buildCatchFormData(rec, photo, photoName) {
  const fd = new FormData()
  fd.append("catch[client_uuid]", rec.client_uuid)
  fd.append("catch[species_id]", rec.species_id)
  fd.append("catch[length_inches]", rec.length_inches)
  if (rec.length_unit) fd.append("catch[length_unit]", rec.length_unit)
  fd.append("catch[captured_at_device]", rec.captured_at_device)
  if (rec.captured_at_gps) fd.append("catch[captured_at_gps]", rec.captured_at_gps)
  if (rec.latitude != null) fd.append("catch[latitude]", rec.latitude)
  if (rec.longitude != null) fd.append("catch[longitude]", rec.longitude)
  if (rec.gps_accuracy_m != null) fd.append("catch[gps_accuracy_m]", rec.gps_accuracy_m)
  if (rec.app_build) fd.append("catch[app_build]", rec.app_build)
  if (rec.note) fd.append("catch[note]", rec.note)
  if (rec.tag_number) fd.append("catch[tag_number]", rec.tag_number)
  if (rec.weight_text) fd.append("catch[weight_text]", rec.weight_text)
  if (rec.queued_by_user_id) fd.append("catch[queued_by_user_id]", rec.queued_by_user_id)
  if (rec.video_failed) fd.append("catch[video_failed]", "true")
  fd.append("catch[photo]", photo, photoName)
  // An unreadable or oversized video must not strand the catch — the photo is
  // the required part. Oversized would bounce off the server's cap (or a
  // proxy 413) and mark the whole catch failed, so drop it client-side.
  if (rec.video && (rec.video.size == null || rec.video.size <= MAX_VIDEO_BYTES)) {
    const video = await materialize(rec.video)
    if (video) {
      const ext = (video.type || "").includes("mp4") ? "mp4" : "webm"
      fd.append("catch[video]", video, `video.${ext}`)
    }
  }
  if (rec.teammate_user_id) fd.append("teammate_user_id", rec.teammate_user_id)
  return fd
}
