
(function () {
  "use strict";

  const DB_NAME = "architect-offline";
  const DB_VERSION = 1;
  const STORE_PROJECTS = "home_projects";
  const STORE_META = "meta";
  const STORE_QUEUE = "sync_queue";

  function openDb() {
    return new Promise((resolve, reject) => {
      if (!window.indexedDB) {
        reject(new Error("IndexedDB no disponible"));
        return;
      }
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains(STORE_PROJECTS)) {
          db.createObjectStore(STORE_PROJECTS, { keyPath: "id" });
        }
        if (!db.objectStoreNames.contains(STORE_META)) {
          db.createObjectStore(STORE_META, { keyPath: "key" });
        }
        if (!db.objectStoreNames.contains(STORE_QUEUE)) {
          const q = db.createObjectStore(STORE_QUEUE, {
            keyPath: "id",
            autoIncrement: true,
          });
          q.createIndex("by_created", "created_at", { unique: false });
        }
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error || new Error("No se abrió IndexedDB"));
    });
  }

  function txDone(tx) {
    return new Promise((resolve, reject) => {
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error || new Error("Transacción abortada"));
    });
  }

  function isOnline() {
    return typeof navigator.onLine === "boolean" ? navigator.onLine : true;
  }

  async function saveProjects(list) {
    const db = await openDb();
    const tx = db.transaction([STORE_PROJECTS, STORE_META], "readwrite");
    const store = tx.objectStore(STORE_PROJECTS);
    // Reemplaza snapshot completo del usuario.
    store.clear();
    (list || []).forEach((p) => {
      if (p && p.id) store.put(JSON.parse(JSON.stringify(p)));
    });
    tx.objectStore(STORE_META).put({
      key: "home_projects_snapshot",
      saved_at: new Date().toISOString(),
      count: (list || []).length,
    });
    await txDone(tx);
    db.close();
  }

  async function loadProjects() {
    const db = await openDb();
    const tx = db.transaction(STORE_PROJECTS, "readonly");
    const store = tx.objectStore(STORE_PROJECTS);
    const rows = await new Promise((resolve, reject) => {
      const req = store.getAll();
      req.onsuccess = () => resolve(req.result || []);
      req.onerror = () => reject(req.error);
    });
    await txDone(tx);
    db.close();
    return rows;
  }

  async function getMeta(key) {
    const db = await openDb();
    const tx = db.transaction(STORE_META, "readonly");
    const row = await new Promise((resolve, reject) => {
      const req = tx.objectStore(STORE_META).get(key);
      req.onsuccess = () => resolve(req.result || null);
      req.onerror = () => reject(req.error);
    });
    await txDone(tx);
    db.close();
    return row;
  }

  async function enqueue(entry) {
    const db = await openDb();
    const tx = db.transaction(STORE_QUEUE, "readwrite");
    const payload = {
      ...entry,
      created_at: new Date().toISOString(),
      status: "pending",
    };
    const id = await new Promise((resolve, reject) => {
      const req = tx.objectStore(STORE_QUEUE).add(payload);
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
    await txDone(tx);
    db.close();
    return id;
  }

  async function listQueue() {
    const db = await openDb();
    const tx = db.transaction(STORE_QUEUE, "readonly");
    const rows = await new Promise((resolve, reject) => {
      const req = tx.objectStore(STORE_QUEUE).getAll();
      req.onsuccess = () => resolve(req.result || []);
      req.onerror = () => reject(req.error);
    });
    await txDone(tx);
    db.close();
    return rows.sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)));
  }

  async function removeQueueItem(id) {
    const db = await openDb();
    const tx = db.transaction(STORE_QUEUE, "readwrite");
    tx.objectStore(STORE_QUEUE).delete(id);
    await txDone(tx);
    db.close();
  }

  async function queueCount() {
    const db = await openDb();
    const tx = db.transaction(STORE_QUEUE, "readonly");
    const n = await new Promise((resolve, reject) => {
      const req = tx.objectStore(STORE_QUEUE).count();
      req.onsuccess = () => resolve(req.result || 0);
      req.onerror = () => reject(req.error);
    });
    await txDone(tx);
    db.close();
    return n;
  }

  
  async function flushQueue(apiFetch) {
    if (!isOnline() || typeof apiFetch !== "function") {
      return { synced: 0, failed: 0, remaining: await queueCount().catch(() => 0) };
    }
    const items = await listQueue();
    let synced = 0;
    let failed = 0;
    for (const item of items) {
      try {
        let body = item.body;
        const headers = { ...(item.headers || {}) };
        if (item.body_kind === "json" && body != null && typeof body !== "string") {
          body = JSON.stringify(body);
          headers["Content-Type"] = headers["Content-Type"] || "application/json";
        }
        if (item.body_kind === "formdata_base64" && item.form) {
          const fd = new FormData();
          for (const field of item.form.fields || []) {
            if (field.type === "file") {
              const bin = Uint8Array.from(atob(field.base64), (c) => c.charCodeAt(0));
              const blob = new Blob([bin], { type: field.mime || "application/octet-stream" });
              fd.append(field.name, blob, field.filename || "archivo");
            } else {
              fd.append(field.name, field.value);
            }
          }
          body = fd;
        }
        const res = await apiFetch(item.url, {
          method: item.method || "POST",
          headers,
          body,
        });
        if (!res.ok && res.status !== 409) {
          failed += 1;
          continue;
        }
        await removeQueueItem(item.id);
        synced += 1;
      } catch {
        failed += 1;
        break; // detener si la red cae a mitad
      }
    }
    return { synced, failed, remaining: await queueCount().catch(() => 0) };
  }

  async function fileToQueueFields(file, extraFields) {
    const buf = await file.arrayBuffer();
    const bytes = new Uint8Array(buf);
    let binary = "";
    const chunk = 0x8000;
    for (let i = 0; i < bytes.length; i += chunk) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
    }
    const fields = [
      {
        type: "file",
        name: "file",
        filename: file.name || "archivo",
        mime: file.type || "application/octet-stream",
        base64: btoa(binary),
      },
    ];
    Object.entries(extraFields || {}).forEach(([name, value]) => {
      if (value != null && value !== "") fields.push({ type: "text", name, value: String(value) });
    });
    return fields;
  }

  window.ArchitectOffline = {
    isOnline,
    saveProjects,
    loadProjects,
    getMeta,
    enqueue,
    listQueue,
    queueCount,
    flushQueue,
    fileToQueueFields,
  };
})();
