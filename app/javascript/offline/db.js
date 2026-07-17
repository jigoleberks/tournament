import { openDB } from "idb";

const DB_NAME = "bsfamilies";
const VERSION = 1;

export async function getDB() {
  return openDB(DB_NAME, VERSION, {
    upgrade(db) {
      if (!db.objectStoreNames.contains("catches")) {
        const store = db.createObjectStore("catches", { keyPath: "client_uuid" });
        store.createIndex("status", "status");
      }
    }
  });
}

// Safari evicts all script-writable storage (this DB included) after ~7 days
// without site interaction unless the origin holds persistent storage. Ask
// once per page, on first enqueue — when we demonstrably have data worth
// keeping. Fire-and-forget: a denial changes nothing about how we proceed.
let persistRequested = false;

export async function enqueueCatch(record) {
  if (!persistRequested) {
    persistRequested = true;
    try { navigator.storage?.persist?.() } catch (_) {}
  }
  const db = await getDB();
  await db.put("catches", { ...record, status: "pending", queued_at: Date.now() });
}

export async function pendingCatches() {
  const db = await getDB();
  return db.getAllFromIndex("catches", "status", "pending");
}

export async function failedCatches() {
  const db = await getDB();
  return db.getAllFromIndex("catches", "status", "failed");
}

// Once the server confirms the catch, it owns the data — keeping the local row
// (with its full photo/video blobs) grows IndexedDB without bound, which is
// what invites iOS storage-pressure eviction. Eviction takes the whole DB,
// including catches still waiting to upload, so synced rows are deleted.
export async function markSynced(client_uuid) {
  const db = await getDB();
  await db.delete("catches", client_uuid);
}

// Sweep rows left in status "synced" by versions that kept them. One index
// read per drain; a no-op once legacy rows are gone.
export async function pruneSynced() {
  const db = await getDB();
  const stale = await db.getAllKeysFromIndex("catches", "status", "synced");
  for (const key of stale) await db.delete("catches", key);
}

export async function markFailed(client_uuid, reason) {
  const db = await getDB();
  const rec = await db.get("catches", client_uuid);
  if (rec) await db.put("catches", { ...rec, status: "failed", reason, failed_at: Date.now() });
}

export async function markPending(client_uuid) {
  const db = await getDB();
  const rec = await db.get("catches", client_uuid);
  if (rec) await db.put("catches", { ...rec, status: "pending", reason: null, failed_at: null });
}
