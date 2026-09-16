'use client';

import { openOfflineDb } from './db';

// Cachea lo mínimo necesario para que el técnico pueda seguir viendo
// (no mutando) sus trabajos de hoy sin conexión — item 17 del brief.
export async function cacheReadData(key: string, data: unknown): Promise<void> {
  const db = await openOfflineDb();
  const tx = db.transaction('read_cache', 'readwrite');
  tx.objectStore('read_cache').put({ key, data, cachedAt: new Date().toISOString() });
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

export async function getCachedReadData<T>(key: string): Promise<T | null> {
  const db = await openOfflineDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('read_cache', 'readonly');
    const request = tx.objectStore('read_cache').get(key);
    request.onsuccess = () => resolve(request.result ? (request.result.data as T) : null);
    request.onerror = () => reject(request.error);
  });
}
