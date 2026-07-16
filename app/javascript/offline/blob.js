// WebKit stores an IndexedDB blob as a FILE on disk and hands back a Blob that
// only REFERENCES that file. When it fails to stream that file into a fetch
// body it sends the request with NO body at all rather than throwing — the
// server then sees zero params. That is what stranded catches on the 2026-07-15
// league night (595 empty-bodied 400s). Copying the bytes into memory detaches
// the Blob from its file backing, which fixes it.
//
// Returns a fresh in-memory Blob, or null if the blob is missing/unreadable/empty.
export async function rematerialize(blob) {
  if (!blob) return null
  try {
    const bytes = await blob.arrayBuffer()
    if (!bytes || bytes.byteLength === 0) return null
    return new Blob([bytes], { type: blob.type || "image/jpeg" })
  } catch (_) {
    return null
  }
}
