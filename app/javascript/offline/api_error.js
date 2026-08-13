// One spelling of "turn an /api/catches refusal into a human-readable reason",
// shared by the background drain (offline/sync.js) and the recover tool
// (controllers/recover_controller.js) so the two can't drift. The API's
// refusals (including the shared-phone queued_by_mismatch) arrive as
// {errors: [...], code: ...} JSON; a non-JSON body (reverse-proxy 413 page,
// etc.) must still produce a readable reason — never raw JSON or "{}".
export async function readApiError(resp) {
  const body = await resp.json().catch(() => null)
  const reason = body && Array.isArray(body.errors) && body.errors.length
    ? body.errors.join(", ")
    : `Upload failed (server error ${resp.status})`
  return { code: body ? body.code : undefined, reason }
}
