'use client';

// IndexedDB nativo — sin librerías externas. Dos object stores:
// - queue: mutaciones pendientes de sincronizar (item 17-18 del brief)
// - read_cache: datos de solo lectura del día (item 17), para que la
//   pantalla "Today" siga siendo útil sin señal.

const DB_NAME = 'kcc-marine-cloud-offline';
const DB_VERSION = 1;

export function openOfflineDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains('queue')) {
        const store = db.createObjectStore('queue', { keyPath: 'id' });
        store.createIndex('status', 'status');
        store.createIndex('workOrderId', 'workOrderId');
      }
      if (!db.objectStoreNames.contains('read_cache')) {
        db.createObjectStore('read_cache', { keyPath: 'key' });
      }
    };

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}
