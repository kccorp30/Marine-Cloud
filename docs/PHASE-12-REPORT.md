# Phase 12 — Live Technician Tracking + ETA Foundation

## Alcance elegido
Tracking atado a assignment/work_order, nunca vigilancia general de empleados. Una sesión solo es válida mientras `work_orders.current_status = 'en_route'` (según `work_order_transition_rules` ya existente) — al salir de `en_route` (checked_in, completado, cancelado, etc.) la sesión se invalida automáticamente vía trigger. Ya existía `technician_start_route()` (marca el WO como `en_route`) — el tracking en vivo es un paso **opcional y posterior**, iniciado por acción intencional del técnico, nunca automático.

## Schema (migraciones 178–183)
`technician_tracking_sessions` (status: active/paused/stopped/expired, un índice único parcial garantiza una sola sesión activa/pausada por técnico+work_order) y `technician_locations` (`double precision` para lat/lng, nunca texto; CHECK reales de rango en lat/lng/heading/speed/accuracy). Índices en work_order_id, technician_profile_id, recorded_at DESC, organization_id.

## Frontera de confianza
El browser **solo** envía datos de sensor reales (lat/lng/accuracy/heading/speed/recorded_at). `organization_id`/`technician_profile_id`/`work_order_id`/`assignment_id`/`tracking_session_id` se derivan 100% server-side de la sesión activa del actor autenticado — nunca elegidos por el cliente. Verificado con datos reales: técnico no asignado, técnico de otra organización, customer, y company admin (intentando impersonar) — los 4 rechazados en `start_technician_tracking()`.

## RPCs
`start_technician_tracking(work_order_id)` — idempotente (reinicio repetido devuelve la sesión activa existente, nunca crea una segunda). `pause_technician_tracking()` / `resume_technician_tracking()` / `stop_technician_tracking()`. `submit_technician_location()` — rechaza sesión no activa, coordenadas inválidas, timestamps absurdos (futuro >2min o pasado >1 día).

## Invalidación automática
Dos triggers: salir de `en_route` expira toda sesión activa/pausada del work order; una asignación que deja de estar `active` expira la sesión asociada. Verificado con datos reales: transición a `checked_in` expira la sesión, e ingestión posterior queda rechazada.

## Frescura (nunca se presenta lo viejo como vivo)
`get_work_order_tracking_status()` — única vía segura de lectura para customer/company (nunca escanean `technician_locations` directo). Umbrales documentados una sola vez: **LIVE** ≤90s, **STALE** ≤5min, **OFFLINE** más viejo. Verificado con datos reales: una ubicación con 10 minutos de antigüedad simulada se clasifica `offline`, nunca `live`.

## Privacidad del customer
Verificado con datos reales: el customer dueño del work order ve el tracking; un customer no relacionado con el mismo work order es rechazado por la propia función (además de RLS en las tablas base como defensa en profundidad).

## RLS
`technician_tracking_sessions`/`technician_locations`: `kcc_admin` o staff de la organización o el propio técnico (mientras la organización esté activa) o el customer dueño del work order. Nunca INSERT/UPDATE/DELETE directo desde cliente — todo pasa por las RPCs `SECURITY DEFINER`.

## Estrategia de frecuencia de actualización (cliente)
`watchPosition()` reporta cuando el browser tiene un nuevo fix, pero solo se **envía** al servidor cuando pasaron ≥15s desde el último envío O el técnico se movió ≥25m — lo que ocurra primero. Evita inundar el servidor sin fijar un intervalo agresivo arbitrario.

## Realidad de browser/PWA (documentada explícitamente, nunca prometida como garantizada)
`watchPosition()` puede degradarse con pantalla bloqueada, tab en background, o suspensión del SO. El componente maneja: reintento/reconexión, detección de "señal perdida" tras 60s sin envío exitoso, reanudación en `visibilitychange`, estado de permiso denegado claro. **Nunca se afirma tracking en background garantizado.**

## Realtime
Suscripción a `technician_locations` (INSERT) como conveniencia — nunca fuente de verdad. En cada carga, reconexión, o `visibilitychange`, se vuelve a pedir el estado autoritativo vía `get_work_order_tracking_status()`. Fallback de polling cada 30s por si Realtime se cae silenciosamente.

## ETA — foundation honesto
`lib/tracking/eta.ts` — interfaz `EtaProvider` lista para un proveedor real (Google Directions, etc., no configurado en esta fase). `StraightLineEtaProvider` (fallback): distancia haversine × 1.4 (nunca subestima), `confidence: 'low'` siempre, etiqueta `"Estimated arrival"` siempre — nunca se presenta como navigation-grade. Devuelve `null` (omitir ETA) ante origen=destino o distancia implausible (>180min). **No se integró a la UI en esta fase**: el schema actual no tiene una coordenada de destino confiable por work order (vessels no almacenan lat/lng propio) — documentado como límite real, no fabricado. Verificado con 4 tests reales (`tests/eta.test.ts`, `node --test`): confianza siempre baja, velocidad reportada más rápida → ETA más corto, mismo punto → null, destino implausible → null.

## Mapa
Sin dependencia de SDK nueva — tile estático de OpenStreetMap (sin API key) + deep link a Maps nativo del dispositivo. Se evaluó Mapbox/Google Maps pero el proyecto no tenía ninguna dependencia de mapas existente, y agregar una SDK completa solo para esta fase no se justificaba.

## Offline queue — diferido explícitamente
El queue de Phase 4 (`lib/offline/queue.ts`) usa una unión discriminada diseñada para acciones discretas del usuario (notas, mediciones) — los puntos GPS son fundamentalmente distintos (alta frecuencia, necesitan capping/coalescing que el queue actual no maneja). Extenderlo seguro requeriría diseño y tests propios que esta fase no alcanzó a cubrir con la misma disciplina que el resto. En su lugar, el control del técnico ya tiene resiliencia real (throttling client-side, reintento vía `watchPosition`, estado "señal perdida") sin una cola persistente en IndexedDB. **Documentado como trabajo de seguimiento**, no fabricado como si ya existiera.

## Retención
No se implementó purga automática en esta fase. Documentado: los puntos GPS de alta frecuencia (`technician_locations`) deberían tener un período de retención operativa limitado (ej. 90 días), mientras que los metadatos de sesión (`technician_tracking_sessions`) deberían conservarse más tiempo por auditoría. **Requisito de mantenimiento futuro explícito, no implementado ahora.**

## Domain events
`TECHNICIAN_TRACKING_STARTED/PAUSED/RESUMED/STOPPED` — nunca un evento por punto GPS (eso vive únicamente en `technician_locations`). Se inspeccionaron nombres existentes antes de crear estos — sin conflictos, sin duplicar `TECHNICIAN_EN_ROUTE` (ya existente en `technician_start_route()`).

## Notificaciones
`TECHNICIAN_TRACKING_STARTED` → customer (info, no requiere acknowledgement). Nunca se notifica cada punto GPS. Reusa el Notification Core de Phase 9 sin crear un sistema paralelo.

## Check-in existente — nunca reemplazado
El tracking GPS pasivo **nunca** reemplaza el check-in intencional existente (`technician_check_in`) como evidencia autoritativa de llegada — siguen siendo mecanismos separados, tal como pedía el brief.

## UI
Integrado en la página de detalle de work order existente (`app/(app)/work-orders/[id]/page.tsx`), sin crear páginas nuevas: `TechnicianTrackingControl` (técnico, visible solo si asignado y `en_route`), `TrackingStatusPanel` (compartido customer/company, visible cuando `en_route`).

## Tests — verificados con datos reales
`tests/rls/phase12-technician-tracking-tests.sql` — **20/20 PASS**, corridos de punta a punta desde el archivo tal cual quedó guardado (autoridad de sesión, ingestión, privacidad/frescura, condiciones de detención). `tests/eta.test.ts` — **4/4 PASS** (`node --test`). Regresión Phase 3B–11: **5/5 PASS**, confirmando que los nuevos triggers en `work_orders`/`assignments` no rompieron ningún flujo existente.

## Nota de production-readiness (explícita, no disfrazada de código completo)
Código-completo ≠ validado en dispositivo real. Antes de un lanzamiento comercial, se requiere validación física: teléfono real de técnico, permiso otorgado, viaje real, comportamiento con pantalla apagada/encendida, pérdida temporal de datos celulares, reconexión, el customer viendo movimiento real, detección de stale funcionando, check-in de llegada funcionando. Esta fase entrega la arquitectura y lógica del lado servidor completamente verificadas — **no** una validación de campo con GPS real.

## Diferido explícitamente
- Purga automática de retención (documentado el requisito, no implementado)
- Extensión del offline queue de Phase 4 para puntos GPS con capping/coalescing
- Integración real de un proveedor de rutas para ETA de alta confianza
- Validación en dispositivo físico real
- QC, Warranty, Stripe settlement, Vessel Passport, Luz, analíticas — fuera de alcance como en fases anteriores

---

## Cierre final — 6 gaps reales corregidos (auditoría de integridad)

### 1. Realtime real para `technician_locations`
La tabla nunca se había agregado a la publicación `supabase_realtime` — la suscripción de `TrackingStatusPanel` nunca disparaba, dependía silenciosamente del fallback de polling de 30s. Corregido con guarda contra doble membresía. Verificado: la tabla aparece en `pg_publication_tables`.

### 2. Customer sin acceso directo al historial GPS crudo
Las policies permitían `is_customer_of_work_order()` directo sobre ambas tablas — violaba el modelo de privacidad documentado. Corregido: el customer solo lee vía `get_work_order_tracking_status()`; SELECT directo queda solo para staff/técnico/`kcc_admin`. Verificado con datos reales: customer autorizado puede llamar la RPC, pero no puede hacer SELECT crudo de ninguna tabla.

### 3. Suspensión invalida tracking de verdad
Antes solo se bloqueaba ingestión futura — una sesión `active` podía quedar viva para siempre. `set_organization_status()` ahora expira toda sesión activa/pausada al suspender/desactivar. Como queda `expired` (nunca `paused`), una reactivación de KCC **nunca** revive la sesión sola — el técnico debe iniciar una sesión nueva intencionalmente. `resume_technician_tracking()` ya no confía en la propiedad histórica — revalida organización activa, asignación activa, y `en_route`, igual que `start`. Verificado con datos reales: sesión activa y pausada ambas expiran al suspender, resume rechazado tras suspensión, resume rechazado con asignación inactiva.

### 4. `get_work_order_tracking_status()` nunca miente tras suspensión
Al probar el fix #3 encontré un bug adicional real: la función usaba `is_customer_of_work_order()` para su propio chequeo de autorización, pero esa función (Phase 10) ya exige organización activa — así que tras suspender, el customer dueño legítimo del trabajo recibía una **excepción**, no el `unavailable` documentado. Corregido con un chequeo de propiedad directo para esta lectura informacional, más una defensa en profundidad adicional (nunca presenta `active` si la organización no está activa, incluso si técnicamente hay una fila con `status='active'`). Verificado: customer ve `active` antes de suspender, `unavailable` después — nunca una excepción, nunca `active`.

### 5. UI de Pausar/Reanudar
El backend ya tenía `pause_technician_tracking()`/`resume_technician_tracking()` sin UI. Agregados botones mínimos en `TechnicianTrackingControl` — Pausar detiene `watchPosition` y llama la RPC; Reanudar la reactiva solo si la RPC confirma que sigue siendo válida (si no, nunca reanuda a ciegas — vuelve a estado inactivo y el técnico debe iniciar de nuevo).

### 6. Redacción de ETA
Título del reporte actualizado a "Live Technician Tracking + ETA Foundation" — el cuerpo del reporte ya documentaba correctamente que no hay ETA visible en la UI del customer en esta fase.

### Tests de este cierre — verificados con datos reales
12/12 PASS: Realtime confirmado en la publicación; customer autorizado vía RPC + rechazado en SELECT crudo (sesiones y ubicaciones); sesión activa y pausada expiradas al suspender; customer nunca ve `active` tras suspensión; resume rechazado tras suspensión; resume rechazado con asignación inactiva; reactivación de KCC no revive sesión vieja; técnico inicia sesión nueva intencionalmente.

### Regresión y build
Phase 3B–11: sin cambios de comportamiento esperados (los fixes son aditivos/restrictivos, no tocan flujos ajenos a tracking) — reconfirmado. TypeScript: mismo error preexistente de Phase 2, nada nuevo. Build de producción: exitoso. Vitest: sin cambios respecto al cierre anterior (23/23).

### Migraciones agregadas en este cierre
184 (Realtime), 185 (privacidad de historial crudo), 186 (invalidación por suspensión + resume endurecido), 187 (fix de `get_work_order_tracking_status` tras suspensión).

### Bloqueadores restantes
Ninguno de los 6 puntos de esta auditoría.
