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

// New-format records store { bytes: ArrayBuffer, type, name, size } instead of
// a Blob — ArrayBuffers serialize inline in the IndexedDB record, so the
// file-backed-blob failure mode above can't occur for them. Legacy records
// (a bare Blob/File) still go through rematerialize. The instanceof check must
// come FIRST: Blob has a .bytes() METHOD, so a "does it have bytes?" probe
// would misroute every legacy record into the ArrayBuffer branch.
export async function materialize(stored) {
  if (!stored) return null
  if (stored instanceof Blob) return rematerialize(stored)
  if (stored.bytes instanceof ArrayBuffer) {
    if (stored.bytes.byteLength === 0) return null
    return new Blob([stored.bytes], { type: stored.type || "image/jpeg" })
  }
  return null
}
