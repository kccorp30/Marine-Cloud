# Known Limitations — Phase 2 Offline Hardening

## Sobre el testing del flujo offline real

Este entorno de trabajo no tiene un navegador real. Pero **sí tiene cobertura automatizada real** de la mecánica del cliente vía `vitest` + `fake-indexeddb` (`tests/offline/queue.test.ts`, `tests/offline/sync.test.ts` — **12/12 PASS**, corridos en vivo):

**Verificado con tests automatizados de verdad (no solo revisión de código):**
- `queue.ts` guarda un `Blob` real en IndexedDB para fotos — no un data URL de texto (`queue.test.ts` lo verifica explícitamente comparando el tipo del valor guardado)
- `sync.ts` enruta cada tipo de item de cola a su función del servidor correcta, con los campos correctos (`sync.test.ts`, servidor mockeado)
- Un item solo se saca de la cola cuando el sync confirma éxito — si falla, queda visible con estado `failed`, nunca se descarta solo
- El orden de sincronización respeta `createdAt` (importante para checklist: una corrección posterior a una respuesta original)

**Sigue sin verificarse con un navegador real** (esto sí requeriría un dispositivo/navegador real, no algo resolvible con más tests del mismo tipo):
- Que `navigator.onLine`/los eventos `online`/`offline` de un navegador real disparan el sync tal como asume el código
- El comportamiento real de cuota de almacenamiento del dispositivo cuando IndexedDB se llena de verdad
- La cámara del dispositivo (`<input capture="environment">`) en distintos navegadores/SO móviles
- Que el upload real a Supabase Storage con una URL firmada funciona end-to-end en condiciones de red reales (los tests de `sync.test.ts` mockean `uploadToSignedUrl`, no lo ejecutan de verdad)

Recomendado como paso técnico antes de producción: correr el flujo completo (foto offline → reconexión → confirmar en Supabase Storage que el objeto real existe) en un dispositivo o navegador real al menos una vez.

## Otras limitaciones conocidas

- Notas de voz: `media_assets` soporta `category='voice_note'`, pero no hay UI de grabación construida (foundation, no feature completa — así estaba planeado)
- Iconos PWA siguen siendo placeholder — sin assets de marca reales
- Timer requiere conexión en v1 — decisión explícita documentada en el código (`lib/offline/queue.ts`), no un olvido
- `vitest`/`fake-indexeddb` son `devDependencies` — nunca se empaquetan en el build de producción, solo corren en desarrollo/CI
- `npm audit` reporta 5 hallazgos (1 crítico) en `esbuild`/`vite`, dependencias transitivas de `vitest` — **100% dev-only, no runtime**, mismo criterio de categorización que se aplicó en el sitio web (`docs/security-review.md` de `kccorp-web`). El fix requeriría `vitest@4.x` (breaking, cambiaría la API de los tests que ya pasan) — no se forzó, siguiendo la misma disciplina de "sin upgrades a ciegas" ya establecida en este proyecto

