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

export async function enqueueCatch(record) {
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

export async function markSynced(client_uuid) {
  const db = await getDB();
  const rec = await db.get("catches", client_uuid);
  if (rec) await db.put("catches", { ...rec, status: "synced", synced_at: Date.now() });
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
