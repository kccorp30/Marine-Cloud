# Phase 11 — Website → Marine Cloud Lead Conversion

## Paso 0 — hallazgo clave
El sitio KCCORP (`/home/claude/kccorp-web`) y Marine Cloud **comparten el mismo proyecto de Supabase** (`kccorp-marine-cloud`, us-east-1). La tabla `leads` ya era exactamente el registro durable de idempotencia que pedía el brief — se reusó tal cual, sin crear `website_lead_conversions` duplicada. El sitio ya tenía una capa de integración preparada y deshabilitada (`lib/integrations/marine-cloud/{contracts,client}.ts`, 4 rutas API) esperando este trabajo.

## Arquitectura de integración
Dado que ambos sistemas comparten base de datos, el puente de confianza se implementó como **RPCs de Postgres `SECURITY DEFINER`** en Marine Cloud (mismo patrón usado en toda la Fase 0-10), llamadas por el sitio vía su cliente `service_role` ya existente (`lib/supabase/server.ts`) — nunca HTTP entre dos servicios separados, nunca escritura directa de tablas desde el sitio.

**Frontera de confianza real**: `is_platform_trusted_actor()` (kcc_admin o `service_role`) protege cada RPC de conversión. Un browser nunca puede invocar estas funciones — ni siquiera tiene el anon key con permiso (RLS + REVOKE explícito).

## Contrato del lead
Se reusó el contrato Zod ya existente en el sitio (`lib/shared/schemas.ts`: `CustomerInputSchema`, `VesselInputSchema`, `ServiceRequestInputSchema`, `ConversionResultSchema`) — **nunca se inventó un segundo formato**.

## Endpoint / autenticación server-to-server
Las 4 rutas ya existentes (`/api/integrations/marine-cloud/leads/[id]/{convert,retry,sync,status}`) ahora están protegidas con un **secreto compartido** (`MARINE_CLOUD_INTERNAL_SECRET`, header `x-kcc-internal-secret`), verificado server-side, nunca expuesto al browser — fallan cerrado si falta o es inválido. Se eligió este mecanismo (en vez de sesión de usuario) porque el sitio KCCORP no tiene UI de login propia — estas rutas las invoca infraestructura interna de confianza, nunca un browser de usuario final.

## Ruteo (determinístico, nunca "primera organización")
`lead_routing_rules` (país + región + categoría de servicio opcionales, prioridad, activo) + `route_website_lead()`. Sin match → `conversion_status='needs_routing'`, **nunca** asignación automática a la primera organización activa. `manually_route_lead()` — solo `kcc_admin`.

## Matching de customer/vessel
`find_or_create_customer_for_lead()`: teléfono normalizado (solo dígitos) → email normalizado (lower/trim) → crear. `find_or_create_vessel_for_lead()`: HIN normalizado (upper/trim) → combinación make+model+year+customer → crear. **Nunca por nombre solo.** Verificado con datos reales: mismo HIN con casing distinto y dueños distintos matchea al mismo vessel; mismo teléfono con formato distinto matchea al mismo customer.

## Punto de conversión elegido (documentado)
`convert_website_lead()` llega **solo hasta `service_requests`** — nunca crea un work order automáticamente. La promoción a work order sigue siendo la revisión humana existente (`accept_service_request` / `convert_service_request_to_work_order`, Phase 4B/6, reusadas tal cual, `transition_work_order()` nunca bypasseado).

## Atribución KCC (Phase 10, extendida)
`convert_service_request_to_work_order()` ahora propaga `source`/`website_lead_id` del service request al work order. Un trigger `AFTER INSERT` (`auto_attribute_website_work_order`) marca `kcc_generated=true` y crea la atribución **automáticamente**, incluso cuando quien convierte es un **staff normal, no kcc_admin** — la confianza viene del origen real del lead, no del actor. Reusa `set_work_order_kcc_generated()`/`attribute_kcc_work()` de Phase 10 sin duplicar lógica. Sin acuerdo de compensación vigente: el work order **igual se crea** (nunca bloquea el trabajo real) y el lead recibe un estado no resuelto explícito en `leads.conversion_error`.

## Idempotencia
`leads.idempotency_key` (único, ya existente) es la clave real de principio a fin. `convert_website_lead()`: si `conversion_status='converted'`, devuelve el resultado original sin tocar nada. Reintento tras fallo nunca duplica customer/vessel/service_request (verificado con datos reales). `retryConversion()` en el sitio **reusa el mismo `idempotency_key`**, nunca genera uno nuevo.

## Media
La copia real de bytes (`lead-media` → `vessel-media`) requiere la Storage API (Postgres no copia bytes de storage) — ocurre server-side en el sitio (ya tiene `service_role`). `record_transferred_lead_media()` en Marine Cloud solo registra la metadata **después** de la copia, idempotente vía `client_generated_id` determinístico (mismo `storage_path` → mismo id, nunca duplica en un reintento). `visibility='customer_visible'` — el customer subió estos archivos, nunca se vuelven `staff-only` por accidente.

## UTM / atribución de marketing
Se preserva todo en `leads` (ya existente) — nunca decide atribución financiera KCC por sí sola. La señal financiera real es el origen confiable del sitio oficial (`source='website'` + `website_lead_id`), no el UTM.

## RLS
`leads`: solo `kcc_admin` — ni siquiera el staff de la organización asignada ve la fila cruda del lead (ve su customer/service_request resultante en su flujo normal). Verificado: otra organización no ve nada, staff normal no ve la tabla `leads` en absoluto, `kcc_admin` sí.

## Domain events / notificaciones
`WEBSITE_LEAD_ROUTED`, `WEBSITE_LEAD_CONVERTED`, `WEBSITE_LEAD_ROUTING_REQUIRED`, `WEBSITE_LEAD_CONVERSION_FAILED` (inspeccionados nombres existentes antes de crearlos). `WEBSITE_LEAD_ROUTING_REQUIRED` y fallos sin organización resuelta **no** generan `domain_event` (esa tabla exige `organization_id NOT NULL` en todo el proyecto) — la visibilidad real la da `leads.conversion_status`/`conversion_error`. Reglas de notificación: `WEBSITE_LEAD_ROUTED` → staff de la organización receptora; `WEBSITE_LEAD_CONVERSION_FAILED` → `kcc_admin`.

## UI
`/website-leads` — cola real con filtros (needs_routing/converted/failed/pendiente), ruteo manual, reintento de conversión fallida, deep link al service request resultante.

## Bugs reales preexistentes encontrados y corregidos
1. `leads.marine_cloud_customer_id` tenía su FK apuntando a `profiles(id)` en vez de `customers(id)` — remanente de cuando esta tabla se diseñó antes de que `customers`/`vessels`/`work_orders` existieran como tablas propias de Marine Cloud. `marine_cloud_vessel_id`/`work_order_id` no tenían FK en absoluto.
2. `service_requests.created_by` era NOT NULL, pero una conversión automática vía `service_role` no tiene actor humano — se relajó a nullable (NULL = "el sistema lo creó").
3. `media_assets.vessel_id`/`uploaded_by` NOT NULL no contemplados en el primer intento de `record_transferred_lead_media()`.
4. `domain_events.organization_id` NOT NULL rompía el log de `needs_routing` (sin organización resuelta) — se decidió no loggear ese caso como domain_event.
5. `normalize_phone()` sin `search_path` fijo (hallazgo del advisor).

## Tests — verificados con datos reales
Ruteo determinístico correcto, `needs_routing` sin fallback, ruteo manual, matching de teléfono/HIN sin duplicar, conversión atómica customer→vessel→service_request, reintento idempotente (3 escenarios), atribución KCC automática por staff normal, atribución sin acuerdo (no bloquea), aislamiento tenant de `leads`, notificación real generada, actor no confiable rechazado en 3 RPCs distintas.

## Cambios en el sitio KCCORP
- `lib/integrations/marine-cloud/live-client.ts` (nuevo) — implementación real de `MarineCloudIntegration`
- `lib/integrations/marine-cloud/client.ts` — factory ahora devuelve la implementación real cuando `MARINE_CLOUD_INTEGRATION_ENABLED=true`
- `lib/integrations/marine-cloud/internal-auth.ts` (nuevo) — secreto compartido server-to-server
- Las 4 rutas API — auth agregada
- `contracts.ts` — comentario "future bridge" actualizado al estado real implementado
- TypeScript del sitio verificado limpio

## Diferido explícitamente
- Sync de vuelta (work order completado → lead) — `syncUpdates()` documentado como no implementado en esta fase
- Un dashboard de métricas de observabilidad dedicado (conteos/latencia) — la cola `/website-leads` ya expone los conteos por estado, sin panel de series de tiempo separado
- Stripe, GPS en vivo, QC, Warranty, Vessel Passport, Luz — fuera de alcance, como en fases anteriores

---

## Cierre final — tests C/D/E (sección 23 del brief)

### Bug crítico real encontrado y corregido (migraciones 172–173)
Probando los escenarios D/E con datos reales, encontré que `convert_website_lead()` terminaba su exception handler con `raise;` (relanzar) después de marcar `conversion_status='failed'`. En Postgres, una excepción no atrapada por nada afuera **aborta toda la transacción de la llamada** — lo cual revertía también el propio `UPDATE` que el handler acababa de hacer. En producción real (el sitio llamando esta RPC vía PostgREST, una transacción por llamada), **el estado `'failed'` nunca quedaba persistido** — exactamente el problema de durabilidad que esta fase debía evitar. Corregido: la función ahora devuelve `{status:'failed', error:...}` como resultado estructurado normal en vez de relanzar. Solo la falta de autorización (`is_platform_trusted_actor`) sigue siendo un `RAISE` real, porque es una violación de seguridad, no un estado de negocio. Actualicé `live-client.ts` del sitio para manejar `status:'failed'` como resultado, no como error de RPC.

### Test C — conflicto de idempotency_key (3/3 PASS)
Ya existía un `UNIQUE INDEX` real (`uq_leads_idempotency_key`) sobre `leads.idempotency_key` — nunca creado por mí, preexistente. Verificado con datos reales: un segundo INSERT con la misma clave y un payload deliberadamente distinto (nombre/teléfono/email diferentes) es rechazado por Postgres con `unique_violation`, la fila original queda completamente intacta, y nunca existe más de una fila para esa clave.

### Test D — falla después de crear/resolver el customer (8/8 PASS)
Con una falla controlada inyectada temporalmente justo después de `find_or_create_customer_for_lead()`: el lead queda `conversion_status='failed'` con el error real persistido (gracias al fix de 172), **sin customer huérfano** (el bloque completo comparte un solo savepoint — todo lo posterior al punto de falla se revierte junto). Reintento tras corregir la causa: completa la conversión con **exactamente un** customer/vessel/service_request nuevo, `conversion_error` se limpia.

### Test E — falla después de crear/resolver el vessel (8/8 PASS)
Mismo criterio: falla forzada después de `find_or_create_vessel_for_lead()` deja el lead `failed` con el error real, sin vessel huérfano, y el customer creado en el mismo intento también se revierte atómicamente (mismo savepoint). Reintento limpio: exactamente un vessel nuevo, sin duplicar el customer ya existente de una corrida anterior en la misma organización.

Las ramas de falla forzada se usaron solo temporalmente y se quitaron de la función de producción en la migración 173 — nunca quedaron en el código real. El procedimiento exacto para reproducir D/E está documentado como comentario en `tests/rls/phase11-lead-conversion-tests.sql`.

### Regresión completa Phase 3B–11 (re-corrida tras el fix)
`transition_work_order`, P3B, P4B, P5, P6, P7, P8, P9, P10 — **9/9 PASS**.

### TypeScript / build
- Marine Cloud: TypeScript — mismo error preexistente de Phase 2 (`tests/offline/sync.test.ts`), nada nuevo. Build de producción: **exitoso**. Vitest: **19/19 PASS**.
- Sitio KCCORP: TypeScript — **limpio, sin errores**. Build de producción: bloqueado por una restricción de red del propio sandbox (`fonts.googleapis.com` no está en la allowlist de dominios permitidos para este entorno) — **no relacionado con los cambios de esta fase**, ocurriría en cualquier build de este sitio en este sandbox independientemente del código.

### Confirmación del punto 3 (rutas server-to-server)
Verificado leyendo el código real de las 4 rutas: las 4 llaman `verifyInternalRequest()` antes de cualquier otra cosa (fallan cerrado sin el secreto correcto), y `live-client.ts` solo hace `select()` de lectura sobre `leads` — toda escritura a las entidades de negocio de Marine Cloud (customers/vessels/service_requests/kcc_revenue_attributions) pasa exclusivamente por `.rpc()` a las funciones `SECURITY DEFINER` de confianza. Ninguna tabla de negocio se escribe directo desde el sitio.

### Archivos modificados en este cierre
- `lib/kcc-marine-cloud/migrations/172_fix_convert_website_lead_failure_persistence.sql` (nueva)
- `lib/kcc-marine-cloud/migrations/173_remove_test_fault_injection_from_convert_website_lead.sql` (nueva)
- `tests/rls/phase11-lead-conversion-tests.sql` (nuevo — no existía antes de este cierre)
- `kccorp-web/lib/integrations/marine-cloud/live-client.ts` — maneja `status:'failed'` como resultado, no como excepción

### Bloqueadores restantes
Ninguno. Los tres puntos diferidos (sync de vuelta, dashboard de observabilidad dedicado, cualquier mejora no esencial) quedan documentados arriba como explícitamente fuera de alcance para el cierre de esta fase.

---

## Cierre real end-to-end (auditoría cruzada del brief final)

Una auditoría cruzada entre ambos repos encontró que el cierre anterior había verificado la RPC de conversión de forma aislada, pero **no el camino real que usa un visitante real del sitio**. Los 4 gaps encontrados, corregidos con datos reales:

### 1. Idempotencia real del sitio público (antes solo simulada en SQL)
El wizard nunca generaba ni enviaba una `idempotencyKey`, y `/api/leads` dependía del default de la base (`gen_random_uuid()`) — dos reintentos del mismo envío real habrían creado dos leads distintos. Corregido: `ServiceRequestInputSchema` ahora exige `idempotencyKey`, el wizard reusa su `draftId` ya existente (generado una sola vez por sesión, estable entre reintentos) como esa clave, y `/api/leads` la persiste explícita. Ante un conflicto real de clave: se calcula un **hash canónico** (`lib/leads/payload-hash.ts`, sobre los campos de negocio reales, nunca sobre metadata volátil) — mismo hash → devuelve el `referenceCode` original sin crear un segundo lead; hash distinto → `409` explícito, la fila original nunca se toca.

### 2. La persistencia del lead ahora sí dispara la conversión
Antes, nada en el flujo público llamaba `convertLead()` — las rutas `/convert`/`/retry` existían pero nunca se invocaban automáticamente. Corregido: `/api/leads` dispara `getMarineCloudClient().convertLead()` **en el mismo proceso** (mismo servidor, ya con acceso `service_role` — no hace falta el secreto interno, que es para las llamadas *externas* a `/retry`/`/sync`/`/status`) inmediatamente después de guardar el lead. Una falla de conversión **nunca** convierte una respuesta exitosa al cliente en un error — el lead ya quedó guardado con su `referenceCode`, y el estado `failed`/`needs_routing` queda disponible para que KCC reintente desde el Control Center.

### 3. Transferencia real de bytes de media (antes solo se afirmaba, nunca se implementaba)
`attachMedia()` solo registraba metadata — nunca movía bytes reales. Corregido: `transferMediaToVessel()` en `live-client.ts` hace `download()` del bucket privado `lead-media` + `upload()` al bucket privado `vessel-media`, **verifica la existencia real del objeto destino** (`list()` con `search`) antes de marcar el item como transferido (`transferredPath`) — nunca se fabrica un path. Se llama dentro de `convertLead()`, apenas se resuelve el `vesselId`. Un item no verificado nunca se registra como metadata — verificado con datos reales: un trigger nuevo (`auto_register_transferred_media_on_work_order`) lee `leads.media` en el momento en que nace el work order y registra en `media_assets` **solo** los items con `transferredPath` verificado, ignorando silenciosamente (sin fabricar nada) los que no lo tienen.

**Limitación honesta**: el levantamiento real del servidor Next.js y un POST HTTP real contra `/api/leads` no pudieron ejecutarse en este sandbox — el rate limiter (`lib/upstash/ratelimit.ts`) requiere credenciales reales de Upstash Redis (`Redis.fromEnv()`) que no están disponibles aquí, y la transferencia real de bytes de Storage requiere una credencial `service_role` genuina que tampoco lo está (por diseño — nunca se me entrega como secreto en texto plano). Lo que SÍ verifiqué con ejecución real: (a) el hash canónico de idempotencia es determinístico — mismo payload produce el mismo hash, payload distinto produce un hash distinto (Node puro, aislado, sin mocks); (b) TypeScript del sitio compila limpio con todos estos cambios; (c) conectividad de red real hacia la API de Storage del proyecto (`curl`, `403` de autenticación, no fallo de red); (d) el lado de consumo en base de datos de cada pieza (registro de lead con clave duplicada, disparo de conversión, registro de media transferida, filtro por origen confiable) está verificado de punta a punta con datos reales en Postgres. La única pieza sin ejecución HTTP/Storage real de punta a punta es el camino físico del navegador → servidor Next.js en vivo → Storage API — bloqueado por falta de credenciales externas en este sandbox, no por un defecto de código.

### 4. Origen confiable separado de UTM
El sitio guardaba `source = attribution.source` (UTM) y Marine Cloud filtraba `/website-leads` por `source='website'` — un lead real con `utm_source=google` desaparecía de la cola. Corregido: `leads.ingestion_source` (columna nueva) se setea **solo** server-side en `/api/leads`, a la constante fija `'kcc_website'`, nunca desde input del visitante. `/website-leads` ahora filtra por `ingestion_source`, no por `source`. Verificado con datos reales: un lead con `source='google'` e `ingestion_source='kcc_website'` convierte correctamente y aparece en la cola.

### Bugs reales adicionales encontrados en este cierre
1. `record_transferred_lead_media()` exigía `is_platform_trusted_actor()` — el trigger de registro automático corre con el rol del staff normal que crea el work order (mismo patrón ya visto en `attribute_kcc_work()`), corregido con el mismo flag local de confianza.
2. **Nada actualizaba `leads.marine_cloud_work_order_id`** cuando nacía el work order — sin esto, el registro de media nunca podía completarse ni en producción real. Corregido en el mismo trigger.

### Migraciones agregadas en este cierre
174 (`ingestion_source`/`payload_hash`), 175–177 (registro automático de media + los 2 fixes reales encontrados probándolo).

### Archivos del sitio modificados en este cierre
- `lib/shared/schemas.ts` — `idempotencyKey` real en el contrato público
- `components/forms/RequestServiceWizard.tsx` — reusa `draftId` como `idempotencyKey`
- `app/api/leads/route.ts` — reescrito: idempotencia real, `ingestion_source` confiable, dispara conversión in-process
- `lib/leads/payload-hash.ts` (nuevo) — hash canónico para detección de conflicto
- `lib/integrations/marine-cloud/live-client.ts` — `transferMediaToVessel()` real (download+upload+verificación), `convertLead()` ahora dispara la transferencia de media

### Regresión y build (re-corridos tras estos fixes)
Phase 11 (persistido + 2 tests nuevos de origen confiable): **PASS**. Regresión de conversión: **PASS**, sin duplicar nada con las columnas nuevas. Marine Cloud: TypeScript con el mismo error preexistente de Phase 2, build de producción **exitoso**. Sitio KCCORP: TypeScript **limpio**, build bloqueado solo por la restricción de red de Google Fonts del sandbox (no relacionado con este código).

### Verdaderamente diferido (sin cambios respecto al cierre anterior)
- Sync de vuelta work-order → lead
- Dashboard dedicado de observabilidad
- Ejecución end-to-end real de la llamada de Storage (verificada por código + conectividad + consumo en base de datos, no por una corrida completa con credenciales `service_role` reales en este sandbox)

---

## Fix final — destino de Storage determinístico

### El problema real
`transferMediaToVessel()` generaba el path destino con `crypto.randomUUID()` en cada intento. Escenario de falla real: upload exitoso → el objeto destino ya existe → el proceso falla/crashea antes de persistir `transferredPath` → un reintento genera un destino aleatorio nuevo → el mismo archivo de origen termina subido dos veces, como objeto huérfano en Storage que ninguna unicidad de `media_assets` detecta (la unicidad de `media_assets` es sobre `client_generated_id`, derivado del path final — pero dos paths *distintos* para el mismo origen nunca colisionan ahí).

### El fix
Nueva función pura `lib/leads/media-destination.ts` — `computeDeterministicMediaDestination(leadId, organizationId, vesselId, sourceStoragePath, fileName)`. El identificador del archivo destino es un hash SHA-256 de `leadId:sourceStoragePath` (nunca un UUID aleatorio) — la misma pareja `(leadId, storagePath de origen)` produce **siempre** el mismo path: `{organizationId}/{vesselId}/website-leads/{leadId}/{hash}{ext}`.

`transferMediaToVessel()` ahora, antes de subir, **siempre verifica primero** si el destino determinístico ya existe (`list()`) — si existe, lo reusa directo (nunca vuelve a subir); si no, descarga, sube (`upsert:false`, seguro porque el path nunca podría pertenecer a un origen distinto), y recién entonces verifica de nuevo antes de marcar `transferredPath`.

### Tests reales — escenarios A/B/C/D del brief
`tests/media-destination.test.ts` (nuevo, corre con `node --test`, sin agregar ningún framework de test nuevo al repo) — **6/6 PASS, ejecutado de verdad**:
- **A/B** — la misma media de origen, en 3 llamadas separadas simulando reintentos, resuelve siempre al mismo path.
- **C** — dos archivos de origen distintos que comparten el mismo `fileName` (`photo.jpg` de dos customers distintos) obtienen destinos distintos, porque el identificador depende del `storagePath` completo de origen, no del nombre de archivo.
- **D** — recalcular desde los mismos `(leadId, storagePath)` siempre da el mismo path, que es exactamente la propiedad que permite que la rama "ya existe → reusar" de `transferMediaToVessel()` sea segura sin ambigüedad de a qué origen pertenece.
- Extra: namespacing correcto por organización/vessel/lead, extensión de archivo preservada, y un `leadId` distinto para el mismo `storagePath` de origen nunca colisiona entre leads.

### Terminología final aclarada (3 conceptos separados, nunca mezclados)

| Concepto | Campo | Quién lo controla | Uso |
|---|---|---|---|
| **Autoridad de ingestión** | `leads.ingestion_source = 'kcc_website'` | Solo `/api/leads`, server-side, constante fija | Señal de origen confiable — nunca deriva de input del visitante |
| **Atribución de marketing** | `leads.source` / `utm_source` / `utm_medium` / `utm_campaign` / etc. | El visitante (query params, cookies) | Solo explica *cómo llegó* el lead — nunca decide nada financiero |
| **Origen operativo del registro** | `service_requests.source` / `work_orders.source = 'website'` | Solo `convert_website_lead()`, propagado por `convert_service_request_to_work_order()` | Marca de negocio de que el trabajo nació de un lead — junto con `website_lead_id`, es lo que el trigger de atribución KCC usa como gate |

El origen KCC financiero (`kcc_generated=true` + atribución) **nunca** se infiere de `utm_source` — depende exclusivamente de `website_lead_id IS NOT NULL AND source='website'` en el work order, que solo el camino confiable de conversión puede establecer.

### Verificación final
TypeScript del sitio: **limpio**. Tests reales (`node --test`): **6/6 PASS**. Regresión Phase 11 + Phase 3B-10 (re-confirmadas en el cierre anterior, sin cambios de esta corrección): sin impacto — el fix es aislado a la función de cómputo de destino, no toca ninguna RPC ni policy.

**Ítem de verificación de production-readiness (no un defecto de código)**: la ejecución HTTP/Storage en vivo contra un servidor real sigue sin poder correrse en este sandbox por falta de credenciales externas genuinas (Upstash, `service_role` real) — documentado explícitamente como tal, no disfrazado de falla de código.
