# Phase 13 — Quality Control + Warranty

## Paso 0 — inspección previa
`quality_control`/`warranty` ya existían como estados en `work_order_transition_rules` (`work_in_progress→quality_control→invoice`, `completed→warranty`) — se reusó ese hook exacto, sin crear un estado de work order competidor. El checklist genérico existente (`checklist_templates`/`checklist_responses`) no tiene semántica de pass/fail a nivel de submission ni ciclo de vida de revisión formal — no alcanzaba para representar QC real, así que se construyó un modelo dedicado (`qc_submissions`/`qc_submission_items`), reusando `media_assets` existente para evidencia (nunca un storage nuevo).

## QC — schema y snapshot
`work_orders.qc_required` (default `false`, opt-in explícito) — snapshot real: una vez seteado, nunca cambia retroactivamente por editar configuración de servicio después. `qc_submissions`: `draft→submitted→passed/failed/cancelled`. Un solo submission "abierto" por work order (índice único parcial) — un fallo se resubmite creando uno nuevo, el anterior queda histórico para siempre.

## QC — autoridad y auto-aprobación
`can_review_qc()` centraliza la autoridad (no repetida en componentes de UI): `company_admin`/`manager`/`kcc_admin` revisan. `technician` prepara/submite evidencia, nunca aprueba. **Política de auto-aprobación**: el actor que hace PASS/FAIL nunca puede ser el mismo que `submitted_by` — salvo `kcc_admin` (override real). Verificado con datos reales: el técnico que submite queda bloqueado de aprobar su propia QC.

## QC → Invoice — el gate real
Extendí `transition_work_order()` (Phase 4B/6, reusada tal cual salvo esta adición) para rechazar específicamente `quality_control→invoice` si `qc_required=true` y no existe una `qc_submissions.status='passed'`. **Nunca depende de ocultar el botón en la UI** — la RPC misma lo rechaza. Verificado con datos reales: bloqueado sin QC pasado, permitido tras pasar, flujo normal intacto cuando `qc_required=false`.

## QC — checklist e items requeridos
`submit_qc_for_review()` rechaza si hay items requeridos en `pending`. `pass_qc_submission()` rechaza si hay items requeridos que no estén en `pass`/`not_applicable`. Verificado con datos reales para ambos casos.

## Warranty — registro real, independiente del status del work order
`warranties` es una tabla propia — nunca depende de `work_orders.current_status='warranty'` (que solo indica ciclo de vida del servicio). Términos **siempre snapshoteados** en `starts_at`/`ends_at` concretos al activar — nunca recalculados si se edita `service_catalog` después.

## Warranty — activación
`activate_warranty()` deriva duración/cobertura de `service_catalog` (nuevas columnas `warranty_enabled`/`warranty_duration_days`/`warranty_coverage_notes`) cuando el work order tiene `service_id` con garantía habilitada — o acepta términos explícitos. **Nunca activa a ciegas** si no hay duración disponible de ninguna fuente.

## Warranty — elegibilidad de claims (nunca solo por status)
`submit_warranty_claim()` compara SIEMPRE la fecha actual contra `starts_at`/`ends_at` reales, nunca confía solo en `status='active'` (sin cron de expiración en esta fase, la elegibilidad server-side sigue siendo correcta igual). Verificado con datos reales: garantía vencida rechaza reclamos nuevos.

## Warranty — trabajo correctivo
`create_corrective_work_order_from_claim()`: el nuevo work order retiene enlaces reales (`warranty_id`, `warranty_claim_id`, `source='warranty_claim'`) — nunca sobreescribe el work order original. **Nunca marca `kcc_generated=true`** (eso solo vía el camino confiable de Phase 10/11). Verificado con datos reales: enlaces preservados, `kcc_generated=false`, historial original intacto.

## Bug real encontrado y corregido en el camino
`work_orders_source_check` no incluía `'warranty_claim'` — `create_corrective_work_order_from_claim()` fallaba con una violación de CHECK real al insertar. Corregido (migración 198) y reverificado.

## RLS
QC: customer nunca lee QC interno (mecánica, notas de fallo, fotos internas) — solo vería un estado simplificado derivado en la app. Staff de la organización, técnico asignado, `kcc_admin` sí. Warranty: customer ve solo SU garantía/reclamo — nunca la ajena. Ninguna mutación directa en ninguna de las 4 tablas nuevas — todo vía RPCs `SECURITY DEFINER`. Verificado con datos reales en ambos módulos: Org B bloqueada tanto en lectura como en escritura.

## Domain events y notificaciones
`QC_STARTED/SUBMITTED/PASSED/FAILED`, `WARRANTY_ACTIVATED/VOIDED/CLAIM_SUBMITTED/CLAIM_APPROVED/CLAIM_REJECTED/CLAIM_RESOLVED` — nombres inspeccionados antes de crearlos, sin duplicados. `QC_SUBMITTED`/`QC_FAILED` → staff; `WARRANTY_ACTIVATED`/`WARRANTY_CLAIM_APPROVED`/`WARRANTY_CLAIM_REJECTED` → customer; `WARRANTY_CLAIM_SUBMITTED` → staff. Verificado con datos reales: notificación real creada al submitir QC.

## Auditoría
`log_audit_event()` en: QC pass/fail (con reviewer), activación/anulación de warranty, aprobación/rechazo de claim — actor, organización, recurso, antes/después, timestamp.

## Contabilidad financiera de garantía — diferida explícitamente
El trabajo correctivo de garantía se factura con el flujo normal existente (`create_invoice`/etc.) — esta fase **no** implementa un mecanismo especial de cobro-cero/cubierto. Documentado como diferido, no fabricado.

## Recordatorios de vencimiento — diferidos explícitamente
No existe infraestructura de scheduler/cron en este proyecto todavía. "Warranty expiring soon" queda documentado como trabajo futuro, no implementado ni simulado.

## Tests — verificados con datos reales
`tests/rls/phase13-qc-warranty-tests.sql` — **24/24 PASS**, corridos de punta a punta desde el archivo tal cual quedó guardado (gate de invoice, autoridad/auto-aprobación, fail/resubmit, aislamiento tenant de QC, activación/privacidad/claims/trabajo correctivo/expiración de warranty). Regresión Phase 3B–12: **6/6 PASS**, confirmando que la extensión de `transition_work_order()` no rompió ningún flujo existente (incluido Phase 12 tracking).

## UI — integrada en el detalle de work order existente
Sin crear páginas nuevas — todo vive en `app/(app)/work-orders/[id]/page.tsx`, siguiendo el mismo patrón ya usado para Phase 12 tracking:

- **`QcPanel`** (staff/técnico, nunca customer): inicio de QC con checklist editable, resultado por item (Pass/Fail/N.A.), Submit para revisión, Pass/Fail para el revisor autorizado, historial de intentos previos fallidos visible. Botones de Pass/Fail deshabilitados hasta que los items requeridos estén resueltos — la UI refleja el mismo gate que ya existe en la base de datos, nunca lo reemplaza.
- **`WarrantyCard`** (customer + staff): estado de cobertura, período, botón "Submit a Claim" solo si la garantía está realmente activa y vigente (mismo chequeo de fecha que el servidor — la UI nunca decide elegibilidad por sí sola, el servidor la revalida siempre). Para staff: Aprobar/Rechazar claims, crear trabajo correctivo.
- **`ActivateWarrantyButton`** (staff, solo cuando el work order está `completed`/`warranty` y no existe garantía todavía): duración + notas de cobertura opcionales.

Verificado: los 10 nombres de parámetro usados en los server actions (`p_work_order_id`, `p_items`, `p_item_id`, `p_result`, etc.) coinciden exactamente con las firmas reales de las RPCs en la base de datos — confirmado consultando `pg_get_function_arguments` directamente, no asumido. TypeScript compila limpio (mismo error preexistente de Phase 2, nada nuevo). Build de producción exitoso — `work-orders/[id]` creció de forma consistente con los componentes nuevos empaquetados.

## Diferido explícitamente
- Contabilidad financiera especial para trabajo correctivo de garantía
- Recordatorios automáticos de vencimiento de garantía (sin infraestructura de scheduler)
- Purga/expiración automática de `warranties.status` por cron (la elegibilidad real de claims ya no depende de esto, verificado)
- QC/Warranty en el portal móvil nativo — fuera de alcance como en fases anteriores

---

## Cierre final — brief de implementación final

### Bugs reales encontrados y corregidos
1. **`can_review_qc()` no verificaba `organizations.status`** — solo la membresía activa. Un manager de una organización **suspendida** seguía teniendo autoridad de revisión de QC. Corregido en la raíz (afecta tanto a `pass_qc_submission()` como `fail_qc_submission()`). Verificado con datos reales: `can_review_qc()` devuelve `false` para org suspendida, y `fail_qc_submission()` queda rechazado.
2. **`fail_qc_submission()` no tenía el chequeo explícito de organización activa** que `pass_qc_submission()` sí tenía — inconsistencia real entre las dos rutas de revisión, corregida.

### `allow_qc_self_approval` — setting real, nunca silencioso
Nueva columna en `organization_settings` (default `false`). Verificado con datos reales el ciclo completo: bloqueado por default incluso cuando el mismo manager submite y revisa su propia QC → habilitado explícitamente → permitido → deshabilitado de nuevo → vuelve a bloquear. `kcc_admin` conserva su override de plataforma en cualquier caso.

### `attempt_number` y `QC_RESUBMITTED` distinto de `QC_STARTED`
`qc_submissions.attempt_number` — contador real por work order. `start_qc_submission()` ahora emite `QC_STARTED` solo en el primer intento y `QC_RESUBMITTED` en los siguientes. Verificado con datos reales: intento #2 tras un fallo incrementa `attempt_number` a 2, `QC_RESUBMITTED` se emite exactamente una vez, `QC_STARTED` sigue apareciendo solo una vez.

### Cola operacional de warranty/claims — gap cerrado
Página nueva `/warranty` (pestañas Warranties/Claims, filtrable por status, deep link al work order de cada fila). `kcc_admin` ve cross-organización; staff de organización ve solo la suya (filtro de query + RLS existente). Agregada al nav de los 3 roles correspondientes. Esto reemplaza la limitación de "solo por work order individual" documentada en el cierre anterior.

### Verificación final tras todos los fixes
Pipeline de QC de punta a punta (start → resolver ítem → submit → pass → invoice) reverificado con datos reales tras aplicar los 4 fixes de esta pasada — sigue funcionando sin regresión. TypeScript limpio (mismo error preexistente de Phase 2). Vitest 23/23. Build de producción exitoso.

### Migraciones agregadas en este cierre final
200 (`can_review_qc`/`fail_qc_submission`/`allow_qc_self_approval`), 201 (`attempt_number`/`QC_RESUBMITTED`).

---

## Cierre de integridad final — 6 gaps reales verificados y corregidos

### 1. `qc_required` real, wireado a los 3 caminos de creación reales
Auditoría confirmó: ningún camino de creación de work orders seteaba nunca `work_orders.service_id` — la columna existe pero no está conectada en la cadena real todavía (gap arquitectónico más profundo, fuera de alcance de este cierre puntual). Diseño real y simple: `organization_settings.qc_required_default` (nunca controlado por el browser) es la fuente de verdad por defecto, con `service_catalog.qc_required` como override real para cuando un work order sí tenga `service_id`. `resolve_qc_required()` es la única función que decide esto — el resultado se snapshotea al crear, nunca se recalcula después. Los 3 caminos reales (`convert_estimate_to_work_order`, `convert_service_request_to_work_order`, `create_corrective_work_order_from_claim`) ahora snapshotean vía esta función. **Verificado con datos reales de punta a punta**: creé un estimate real → lo aproibé → lo convertí a work order con `organization_settings.qc_required_default=true` → confirmé `qc_required=true` en la fila real → cambié la config → confirmé que el work order ya creado NO mutó → llevé ese mismo work order (con su snapshot real, no insertado a mano) hasta `quality_control` → confirmé que `invoice` queda bloqueado sin QC pasado. Mismo patrón verificado para la conversión de service_request.

Configuración real expuesta en `/services`: checkbox de "Require quality control" + campos de warranty por servicio, con toggle rápido en la lista existente — nunca un sistema de configuración paralelo.

**Bug real preexistente descubierto por esta regresión**: `service_requests.source` puede ser `'marine_cloud'` (envío in-app) — nunca se había agregado a `work_orders_source_check`. Cualquier conversión de un service_request in-app a work order fallaba con una violación de CHECK real, sin relación con mis cambios de esta fase. Corregido (migración 209).

### 2. Notificaciones de warranty al customer — ahora resuelven de verdad
`resolve_domain_event_work_order_id()` (Phase 9) no manejaba `entity_type='warranty'` — la resolución de destinatario customer depende de `domain_events.work_order_id`, así que `WARRANTY_ACTIVATED`/`CLAIM_APPROVED`/`CLAIM_REJECTED` nunca generaban notificación real para nadie. Corregido extendiendo el resolver. Unifiqué además `void_warranty()` para usar el mismo `entity_type='warranty'` que el resto (antes usaba `'work_order'`, inconsistente). **Verificado con datos reales, no solo "el evento existe"**: confirmé la fila real en `notifications` con el `recipient_user_id` exacto del customer, para activación, aprobación, y rechazo de claim.

### 3. Máquina de estados de claim completa
`create_corrective_work_order_from_claim()` emitía `WARRANTY_CLAIM_RESOLVED` al crear el trabajo correctivo — evento incorrecto, el claim recién entra a trabajo, no se resolvió. Corregido a `WARRANTY_CLAIM_WORK_CREATED`. Agregadas las transiciones reales faltantes: `mark_warranty_claim_under_review()`, `resolve_warranty_claim()` (persiste `resolved_at`), `cancel_warranty_claim()`. Cada función valida su propio estado de origen exacto — ninguna transición fuera de la lista es posible. **Verificado con datos reales**: ciclo completo `submitted→under_review→approved→in_progress→resolved`, `resolved` no puede volver a `under_review`, `rejected` no puede crear trabajo correctivo, duplicado de trabajo correctivo rechazado.

### 4. Activación de warranty idempotente
`warranties.work_order_id` no era único y `activate_warranty()` no prevenía duplicados. Agregado constraint único real; la función ahora devuelve la garantía existente en reintento, nunca crea una segunda. Defensa en profundidad adicional: si `qc_required=true`, exige QC realmente pasado antes de activar, incluso si el work order llegó a `completed` por otro camino. **Verificado con datos reales**: reintento de activación no duplica.

### 5. Evidencia de QC usable de verdad
La FK única `qc_submission_items.media_asset_id` nunca se usaba desde la UI real. Reemplazada por `qc_evidence` — tabla de unión propia (permite varios archivos por item), reusa `media_assets` existente. `attach_qc_evidence()` valida server-side que el media pertenece al **mismo** work_order/organización — nunca confía en un `media_asset_id` de otro trabajo o tenant. `QcPanel` ahora tiene un selector real de media existente del work order para adjuntar evidencia durante el estado `draft`, y muestra el conteo de evidencia adjunta. **Verificado con datos reales**: media del mismo work order aceptada, media de otro work order rechazada, customer nunca ve `qc_evidence` (RLS), la evidencia se preserva intacta tras pasar la QC.

### 6. Configuración de QC/warranty por servicio — UI real
`/services` ahora expone: checkbox de QC requerido (con toggle rápido en la lista), checkbox de warranty habilitada, duración en días, y notas de cobertura — al crear un servicio nuevo. `ActivateWarrantyButton` ya no presenta un valor de 90 días hardcodeado como si viniera de configuración real — ahora consulta el default real de `service_catalog` (cuando el work order tiene `service_id`) y lo muestra explícitamente como "usando los términos configurados de este servicio", o pide al staff ingresar la duración explícitamente cuando no hay default (el caso más común hoy, dado el gap de `service_id` documentado en el punto 1).

### Verificación final de este cierre
TypeScript limpio (mismo error preexistente de Phase 2, nada nuevo). Vitest sin cambios respecto al cierre anterior. Build de producción exitoso. Regresión ampliada: Phase 6 (estimate→work order) y Phase 4B (service_request→work order) ambas confirmadas snapshoteando `qc_required` correctamente con datos reales, sin mutación tras cambios de configuración posteriores.

### Migraciones agregadas en este cierre de integridad
202 (`resolve_qc_required` + snapshot en `convert_estimate_to_work_order`), 203 (snapshot en los 2 caminos restantes + fix de evento `WORK_CREATED`), 204 (resolver de `entity_type='warranty'`), 205 (máquina de estados de claim completa), 206 (idempotencia de activación + defensa en profundidad de QC), 207 (unificación de `entity_type` en `void_warranty`), 208 (`qc_evidence`), 209 (fix de constraint preexistente `marine_cloud`).

### Bloqueadores restantes
Ninguno de los 6 puntos de este cierre de integridad. El gap arquitectónico más profundo (`work_orders.service_id` nunca poblado en ningún camino real) queda documentado explícitamente como fuera de alcance — el diseño de `resolve_qc_required()` ya lo anticipa y funciona correctamente hoy vía el default de organización, listo para usar el override de catálogo en cuanto ese enlace se conecte en una fase futura.

---

## Cierre verdaderamente final — 5 gaps reales adicionales encontrados y corregidos

### 1. `qc_required` ahora garantizado por trigger real — cierra TODO camino, presente y futuro
Auditoría cruzada encontró una **4ta ruta real** de creación no cubierta: `lib/work-orders/actions.ts createWorkOrder()` inserta directo en `work_orders` con `service_id`, pero nunca seteaba `qc_required` — un work order creado manualmente podía saltarse un requisito de QC. En vez de parchear ese archivo (dejando la puerta abierta a un 5to camino futuro sin auditar), implementé un **trigger `BEFORE INSERT` real** (`enforce_qc_required_snapshot`) que SIEMPRE sobrescribe `NEW.qc_required` con `resolve_qc_required()` — cierra todo camino de creación, presente y futuro, sin depender de que cada desarrollador recuerde llamar al resolver. Solo `BEFORE INSERT`, nunca `BEFORE UPDATE` (snapshot histórico real). **Verificado con datos reales**: servicio con QC true/false, sin servicio (usa default de organización), y — el test más importante — **el browser no puede forjar ni `true` ni `false`**, en ninguna dirección: un INSERT que intenta mandar `qc_required=true` con un servicio configurado en `false` queda en `false`, y uno que intenta mandar `false` con un servicio en `true` queda en `true`. Confirmado también que un `UPDATE` posterior nunca recalcula el snapshot.

### 2. Autoridad de `kcc_admin` completa en las 11 RPCs de QC/Warranty
Auditoría de las 14 RPCs SECURITY DEFINER de esta fase encontró 7 que usaban solo `is_org_staff()` sin fallback a `is_kcc_admin()`: `activate_warranty`, `void_warranty`, `create_corrective_work_order_from_claim`, `attach_qc_evidence`, `start_qc_submission`, `set_qc_item_result`, `submit_qc_for_review`. Corregidas las 7 al patrón ya establecido en el resto del proyecto desde Phase 0: `is_org_staff(...) OR is_kcc_admin()`. La seguridad tenant para usuarios ordinarios nunca se debilitó — `is_org_staff()` sigue exigiendo exactamente lo mismo. **Verificado con datos reales**: un `kcc_admin` **sin membresía** en la organización objetivo activa/anula garantías y crea trabajo correctivo cross-org; Org A sigue bloqueada de operar sobre Org B.

### 3. Máquina de estados de claim wireada a la UI real
`mark_warranty_claim_under_review()`, `resolve_warranty_claim()`, y `cancel_warranty_claim()` (ya existían en SQL desde el cierre anterior) ahora tienen server actions reales (`markClaimUnderReviewAction`, `resolveClaimAction`, `cancelClaimAction`) y controles reales en `WarrantyCard`: `submitted`→[Start Review], `under_review`→[Approve][Reject], `approved`→[Create Corrective Work Order], `in_progress`→[Resolve Claim], y [Cancel Claim] donde el backend lo permite (`submitted`/`under_review`, staff o customer dueño). El backend sigue siendo la única autoridad — la UI nunca asume nada que el servidor no vaya a validar de nuevo. Revalida `/work-orders/[id]` y `/warranty` en cada acción; errores reales se muestran, nunca se silencian.

### 4. Garantía vencida nunca se presenta como activa
`warranty_effective_status()` (SQL) + `getEffectiveWarrantyStatus()` (TS, réplica exacta) — **único lugar** donde se deriva el estado de presentación. Sin infraestructura de cron, `warranties.status` puede seguir diciendo `'active'` con `ends_at` ya vencido — toda la UI (`WarrantyCard`, cola `/warranty`, filtros por status) ahora usa el estado **efectivo**, nunca el crudo. La cola `/warranty` ya no filtra por `status` crudo en la base de datos — trae los candidatos y filtra en memoria por estado efectivo, así que una garantía vencida jamás aparece bajo "Active" ni desaparece de "Expired" solo porque nadie corrió un job de mantenimiento. **Verificado con datos reales y tests ejecutables** (`tests/warranty-effective-status.test.ts`, 4/4 PASS vía vitest): fecha futura → activo, fecha pasada + status almacenado activo → efectivamente vencido, `voided` se mantiene `voided` sin importar la fecha.

### 5. Tests de integridad final — ejecutables de verdad, no comentarios
El bloque final de `tests/rls/phase13-qc-warranty-tests.sql` (sección E) pasó de ser un resumen en comentarios a **16 aserciones SQL reales y ejecutables**, corridas de punta a punta desde el archivo tal cual quedó guardado: snapshot real de `qc_required` en creación manual (con servicio y sin servicio), autoridad `kcc_admin` cross-org, `warranty_enabled=false` nunca usa duración obsoleta, ciclo completo de claim (`submitted→under_review→approved→in_progress→resolved`), evento `WORK_CREATED` correcto (nunca `RESOLVED` falso), `resolved` no puede reabrirse, notificaciones reales de `WARRANTY_ACTIVATED`/`WARRANTY_CLAIM_APPROVED` verificadas por `recipient_user_id` real (no solo que el evento existe), y la función `warranty_effective_status()` real. En el camino encontré y corregí un bug en mi propio fixture de test (customer sin `profile_id` vinculado) — quedó documentado y corregido en el archivo persistido, no solo en esta corrida.

### Verificación final
TypeScript limpio (mismo error preexistente de Phase 2). Vitest **27/27 PASS** (23 previos + 4 nuevos del helper de expiración efectiva). Regresión Phase 3B–12 re-confirmada **7/7 PASS**, incluyendo verificación explícita de que el nuevo trigger de `qc_required` no rompe ningún flujo existente (Phase 3B, 4B, 9, 10, 12). Build de producción exitoso.

### Migraciones agregadas en este cierre verdaderamente final
210 (trigger `enforce_qc_required_snapshot`), 211 (autoridad `kcc_admin` en 3 RPCs de warranty + defensa `warranty_enabled`), 212 (autoridad `kcc_admin` en 4 RPCs de QC), 213 (`warranty_effective_status`).

### Bloqueadores restantes
Ninguno de los 5 puntos de este cierre. El mismo gap arquitectónico documentado en el cierre anterior (`work_orders.service_id` nunca poblado en ningún camino real) sigue siendo el único límite conocido, y el diseño ya lo anticipa correctamente.

---

## Pase final de corrección — 4 gaps reales adicionales

### 1. Volatilidad correcta de `warranty_effective_status()`
La migración 213 declaró la función como `IMMUTABLE`, pero depende de `current_date` — no es inmutable, cambia de resultado entre fechas distintas. Corregido con un `CREATE OR REPLACE` nuevo (migración 214, **nunca se editó 213 retroactivamente**) a `STABLE`, la clasificación correcta de PostgreSQL para una función cuyo resultado es constante dentro de una misma sentencia/transacción pero puede variar entre sentencias. **Verificado con datos reales**: `ayer=expired`, `hoy=active`, `mañana=active`, `voided` se mantiene, y confirmado que `pg_proc.provolatile` ya no marca la función como inmutable.

### 2. Bug real de timezone en la expiración efectiva (TypeScript)
`getEffectiveWarrantyStatus()` comparaba `new Date(endsAt) < new Date(new Date().toDateString())` — para un valor `DATE` tipo `'YYYY-MM-DD'`, JavaScript parsea la fecha como **medianoche UTC**. En timezones de offset negativo (la mayoría de EE.UU.) esto podía hacer que una garantía que vence **hoy** se viera vencida horas antes de que terminara el día local — un bug de negocio real, no cosmético. Corregido comparando **strings de fecha de calendario normalizados** (`YYYY-MM-DD`) directamente, sin construir objetos `Date` para la comparación — la expiración es una regla de fecha de calendario, nunca una comparación de timestamp. SQL y TypeScript ahora tienen semántica idéntica.

**Verificación real, no solo teórica**: antes de aplicar el fix, ejecuté la comparación vieja bajo `TZ=America/Los_Angeles` con la fecha de hoy real — confirmé que efectivamente devolvía `expired=true` para una garantía que vence hoy, probando que el bug era genuino. Después del fix, corrí el mismo test bajo el mismo timezone real (no simulado) y confirmé `active`. Vitest ampliado a 6 tests (antes 4), incluyendo uno que protege explícitamente contra este comportamiento de offset de timezone, documentado en el propio test.

### 3. Filtros de status de claims completos
La cola `/warranty?tab=claims` solo exponía `Submitted`/`Approved`/`Rejected` — la máquina de estados real soporta 7 status. Agregados los filtros faltantes: `Under Review`, `In Progress`, `Resolved`, `Cancelled` (más `All` ya existente). Reusa la query real ya existente (`warranty_claims.status`, sin lógica de ciclo de vida nueva) — solo se agregaron los links de filtro en la UI.

### 4. `WARRANTY_CLAIM_CANCELLED` — evento y auditoría reales
`cancel_warranty_claim()` cambiaba el status a `cancelled` pero nunca dejaba evidencia de dominio/auditoría — una transición de ciclo de vida real sin rastro. Agregado `WARRANTY_CLAIM_CANCELLED` (nombre nuevo, no duplica ninguno de los 8 eventos de warranty ya existentes). La autorización de cancelación (staff, `kcc_admin`, o customer dueño, solo en `submitted`/`under_review`) quedó exactamente igual.

**Bug real encontrado probando esto mismo**: la primera versión usaba `log_audit_event()`, que exige `is_org_staff()`/`is_kcc_admin()`/`is_platform_trusted_actor()` — un customer cancelando su **propia** claim no califica para ninguno de los tres, pese a que `cancel_warranty_claim()` ya validó su autorización real (`is_own_customer_record()`) unas líneas antes. Corregido usando `log_audit_event_internal()` (mismo patrón ya establecido en `transition_work_order()` para este exacto escenario: una función `SECURITY DEFINER` que ya autorizó al actor por su cuenta). **Verificado con datos reales**: un customer cancela su propia claim, el evento y la evidencia de auditoría quedan registrados correctamente.

### Verificación final
TypeScript limpio (mismo error preexistente de Phase 2). Vitest **29/29 PASS**. Regresión puntual re-confirmada. Build de producción exitoso.

### Migraciones agregadas en este pase de corrección
214 (`warranty_effective_status` → `STABLE`), 215 (`WARRANTY_CLAIM_CANCELLED`, con el bug de autoridad de auditoría), 216 (fix del bug de 215 usando `log_audit_event_internal()`).

### Bloqueadores restantes
Ninguno de los 4 puntos de este pase.

---

## Parche final — renderizado de fecha en la UI de warranty

### El problema real
`WarrantyCard` y la cola `/warranty` seguían usando `new Date(warranty.startsAt).toLocaleDateString()` / `new Date(w.endsAt).toLocaleDateString()` directo sobre valores `DATE` de Postgres (`'YYYY-MM-DD'`) — el mismo patrón de bug ya corregido en `getEffectiveWarrantyStatus()`, pero sin aplicar todavía a la parte puramente visual. `new Date('YYYY-MM-DD')` se interpreta como medianoche UTC; en timezones de offset negativo puede mostrar el día calendario **anterior**.

### El fix
`lib/warranty/format-calendar-date.ts` — `formatCalendarDate()`, único formateador para valores `DATE` puros: separa año/mes/día y construye el `Date` a partir de sus componentes numéricos (interpretados como hora local, nunca UTC). Reemplazado en `WarrantyCard` (`startsAt`/`endsAt`) y en la cola `/warranty` (`endsAt`). Barrido completo del área de warranty/QC confirmó que el único otro uso de fecha (`QcPanel`, `s.createdAt`) es un `timestamptz` real, no un `DATE` — se dejó intacto, tal como pide la regla explícita de no tocar timestamps genuinos.

### Verificación real, no solo teórica
Antes de aplicar el fix, confirmé que `new Date('2026-01-01').toLocaleDateString()` bajo `TZ=America/New_York` real (no simulado) mostraba `12/31/2025` — el bug era genuino. Después del fix, `tests/format-calendar-date.test.ts` (5 tests) corrió PASS tanto en timezone default como bajo `TZ=America/New_York` explícito, cubriendo 1 de enero, 10 de septiembre, y 31 de diciembre.

### Verificación final
Vitest **34/34 PASS** (29 previos + 5 nuevos del formateador). TypeScript limpio (mismo error preexistente de Phase 2). Build de producción exitoso. `next lint` no puede correr de forma no interactiva en este repo — nunca se configuró ESLint en ninguna fase anterior; condición preexistente, no introducida por este parche.

### Migraciones agregadas en este parche
Ninguna — cambio puramente de UI, sin tocar base de datos ni lógica de negocio.

### Bloqueadores restantes
Ninguno.
