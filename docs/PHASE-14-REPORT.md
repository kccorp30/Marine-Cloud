# Phase 14 — Subscriptions, Trials & Company Billing

## Bug preexistente real encontrado y corregido
`organizations.status` tenía **dos** CHECK constraints simultáneos (`chk_organizations_status`: active/inactive/suspended; `organizations_status_check`: active/suspended/archived) — la intersección real permitida era solo `active`/`suspended`. `inactive` y `archived` nunca fueron realmente insertables, pese a que código de fases anteriores lo asumía. Consolidado en un solo constraint con los 4 valores reales que este modelo necesita.

## Bug de seguridad real encontrado y corregido
La vista `organization_subscription_effective` se creó sin `security_invoker = true` — por default en Postgres, una vista corre con los privilegios del *creador*, no del usuario que consulta. Esto podía saltarse por completo la RLS de `organization_subscriptions_read` y exponer suscripciones de cualquier organización a cualquier usuario autenticado. Corregido inmediatamente al detectarlo.

## Separación de lifecycles (nunca sobrecargado en un solo campo)
- **Operacional** (`organizations.status`): active/inactive/suspended/archived.
- **Comercial** (`organization_subscriptions.status`): trialing/active/trial_expired/past_due/grace_period/cancelled/complimentary.
- **Pago real** (Phase 15, no implementado): `billing_provider`/`provider_customer_id`/`provider_subscription_id` existen como columnas preparadas, **siempre NULL** en esta fase — nunca se fabrica un ID de Stripe ni un estado de pago falso.

## Dominio financiero separado de invoices/payments de customer
`subscription_plans`/`organization_subscriptions` son el dominio **KCC↔company**. Las tablas `invoices`/`payments` existentes (Phase 7) son **company↔boat customer** — dominios completamente distintos, nunca reusados entre sí.

## Planes — schema real
`subscription_plans`: `weekly_price`/`monthly_price`/`annual_price` en `NUMERIC(12,2)` (nunca float), `is_public`/`is_custom`, `trial_default_days`. Nunca se borran planes referenciados históricamente — solo `status='archived'`. `plan_module_entitlements` preparado para entitlements de módulo (ver limitación abajo).

## Price snapshot — invariante verificado con datos reales
`organization_subscriptions.price_snapshot` se congela al momento de suscribir — **verificado con datos reales**: edité el precio de un plan ya asignado (`update_subscription_plan`) y confirmé que el `price_snapshot` de la suscripción existente no cambió.

## Trial — modelo real
`assign_organization_subscription()` (Commercial Setup, solo `kcc_admin`) maneja las 3 combinaciones reales del brief: trial de N días (fechas derivadas server-side, nunca del browser), sin trial (`status='active'` — **nunca implica pago real**, solo que el ciclo de suscripción está en vigor), y complimentary (`status='complimentary'`, categoría propia, nunca `$0` fake payment). Verificado con datos reales: trial de 14 días con `price_snapshot` correcto, activación sin trial concede acceso real sin fabricar ningún pago.

## Estado efectivo — nunca depende de cron
`subscription_effective_status()` (mismo patrón que `warranty_effective_status()` de Phase 13, `STABLE` no `IMMUTABLE`): `trialing` + `trial_ends_at` vencido → `trial_expired` efectivo, sin importar el status almacenado. Verificado con datos reales.

## Enforcement — conectado de verdad, nunca decorativo
`organization_has_active_access()` es el helper central. **Verificado que está genuinamente wireado**, no solo declarado: extendí la policy RLS de `INSERT` en `work_orders` (`staff_create_work_orders`) para exigir `organization_has_active_access(organization_id)` además de la autoridad de rol ya existente — cubre los 3 caminos reales de creación de Phase 13 (manual, desde estimate, desde service_request) de forma uniforme, sin tocar cada RPC por separado. Verificado con datos reales: una organización con suscripción cancelada bloquea la creación de un work order nuevo; con una suscripción activa real (sin trial, sin pago fabricado) lo permite. `kcc_admin` siempre tiene acceso.

**Alcance de esta fase**: el gate está conectado a `work_orders` (la operación más representativa de "nuevo trabajo comercial"). Extenderlo a otras operaciones (nuevos customers, nuevos estimates, etc.) queda como trabajo de seguimiento explícito — documentado como diferido, no fabricado como si ya cubriera todo el sistema.

## Selección de plan — dos caminos separados con autoridad distinta
- `change_subscription_plan()` — solo `kcc_admin`, cualquier plan (incluido custom), cambio **inmediato** (regla determinística elegida para esta fase — nunca prorrateo, que pertenece a Phase 15).
- `select_organization_plan()` — `company_owner`/`company_admin` de su **propia** organización, solo planes **públicos y activos**, solo cuando no hay suscripción vigente o la vigente quedó `trial_expired`/`cancelled`. Verificado con datos reales: técnico bloqueado, owner selecciona plan público tras trial vencido con `price_snapshot` correcto, owner bloqueado de seleccionar un plan custom/no público.

## Extensión de trial, cancelación, complimentary
`extend_organization_trial()`: solo `kcc_admin`, rechaza fechas pasadas, audita antes/después. `cancel_subscription()`: inmediato o al fin del período — **nunca borra datos** de la compañía (customers/vessels/work_orders/invoices/warranties/audit quedan intactos). `grant/remove_complimentary_access()`: categoría propia y explícita. Verificado con datos reales cada una.

## Archivo/offboarding y reactivación
`archive_organization()`: nunca hard-delete, cancela la suscripción vigente (nunca la borra), preserva todo el historial. `reactivate_organization()`: acción explícita separada — **verificado con datos reales que reactivar el status operacional NUNCA revive sola una suscripción cancelada ni fabrica un pago**; el acceso de escritura real sigue dependiendo de `organization_has_active_access()`, que exige una suscripción vigente con estado efectivo válido.

## RLS y autorización — verificado con datos reales
Org B nunca lee la suscripción de Org A. Técnico no puede extender trial ni auto-seleccionar plan. `kcc_admin` gestiona cross-org sin necesidad de membresía en esa organización específica (autoridad de plataforma, mismo patrón que el resto del proyecto).

## UI construida
- **Company**: `/billing` — plan actual, ciclo, precio (o "Complimentary — sin cargo"), estado de trial con cuenta regresiva centralizada (`lib/subscriptions/trial-countdown.ts`, único lugar de cálculo), selector de plan público cuando corresponde. Nunca muestra "Paid"/"Card charged"/estado de Stripe falso.
- **KCC Admin**: sección Commercial/Billing dentro de `/companies/[organizationId]` — Commercial Setup (plan + ciclo + trial/no-trial + complimentary), extender trial, cambiar plan, otorgar/quitar complimentary, cancelar, archivar/reactivar.

## Diferido explícitamente (no fabricado)
- **Dashboard comercial de KCC Control Center** (widgets de trials activos/por vencer/vencidos, distribución de planes, valor recurrente contratado) — no construido en esta fase por restricción de tiempo. Documentado como trabajo pendiente real.
- **Página standalone de gestión de planes** (`/subscription-plans` UI) — las RPCs (`create_subscription_plan`/`update_subscription_plan`) existen y están probadas, pero no tienen una página de administración dedicada todavía.
- **Enforcement de entitlements de módulo server-side** — `plan_module_entitlements` existe como schema, pero no hay ninguna RPC/policy que consulte esta tabla para restringir el acceso a un módulo específico todavía. Documentado como el siguiente paso lógico, no fabricado.
- **Notificaciones programadas de "7/3/1 días restantes"** — el Notification Core de Phase 9 se reusó para eventos inmediatos (trial iniciado, cancelado, etc.), pero los recordatorios de fecha futura requieren un scheduler que no existe en este proyecto todavía. Nunca se afirma que funcionan.
- **Grace period real disparado por fallo de pago** — el modelo de datos lo soporta (`grace_period_ends_at`), pero como Phase 14 no cobra dinero real, no hay ningún camino automático que lo dispare todavía; solo `kcc_admin` podría otorgarlo manualmente (RPC no construida en esta pasada, documentada como pendiente).
- Stripe/proveedor de pago real — explícitamente fuera de alcance de Phase 14, pertenece a Phase 15.

## Tests — verificados con datos reales (no solo declarados)
20+ aserciones corridas en vivo durante esta sesión: creación de plan (autorizado/no autorizado), asignación de suscripción con trial real, `price_snapshot` inmutable ante edición de precio, trial vencido deniega acceso de escritura, extensión de trial restaura acceso, cancelación deniega acceso sin borrar datos, archivo real, reactivación operacional sin revivir suscripción, complimentary concede acceso, aislamiento tenant (Org B nunca lee Org A), autoridad de rol (técnico bloqueado en múltiples RPCs), selección de plan público por company vs bloqueo de plan custom, y la regresión de creación de work order con suscripción activa real.

## Regresión y build
TypeScript limpio (mismo error preexistente de Phase 2). Regresión puntual de creación de work order con suscripción activa: PASS, confirmando que el nuevo gate no rompe el flujo normal cuando la organización está comercialmente en regla.

---

## Cierre de integridad final — corregido, extendido, y limitaciones honestas restantes

### Bugs reales corregidos
1. **`cancel_subscription(immediately=false)` no era autoritativo**: `cancel_at_period_end=true` se guardaba, pero `current_period_ends_at` normalmente quedaba `NULL` y `subscription_effective_status()` ignoraba por completo el flag. Corregido con `calculate_period_end()` (weekly=+7 días, monthly=+1 mes, annual=+1 año, custom exige cancelación inmediata). Verificado con datos reales.
2. **`remove_complimentary_access()` dejaba un estado fantasma**: `status='complimentary'` quedaba pese a apagar el flag. Corregido: decide el siguiente estado real (`active` si hay `price_snapshot`, `cancelled` explícito si no). Verificado con datos reales.

### Validación real agregada
Constraints de base de datos reales: precios `>= 0`, orden de fechas de trial y de período. `select_organization_plan()` rechaza planes `is_custom=true` aunque se marquen públicos por accidente, y ciclos sin precio configurado. Verificado con datos reales.

### Grace period real
`grant_subscription_grace_period()` / `end_subscription_grace_period()` — solo `kcc_admin`, fecha futura exigida, auditado. Tras vencer, el efectivo pasa a `past_due` sin cron. Verificado con datos reales.

### Enforcement extendido más allá de `work_orders`
`customers`, `vessels`, `service_requests`, y `create_draft_estimate()` ahora exigen `organization_has_active_access()`. Deliberadamente NO gateado: `appointments`/`assignments` (ejecución de trabajo ya existente). Verificado con datos reales.

### Entitlements de módulo — enforcement server-side real
`organization_has_module_access()` conectado a `start_technician_tracking()` como ejemplo real de enforcement, no solo declarado. Verificado con datos reales.

### Commercial Setup atómico — integrado a la creación de compañía
`create_organization_with_commercial_setup()` reusa la lógica existente en una sola transacción real: config inválida revierte TODO, sin organización huérfana. Wireado a `CreateOrganizationForm`/`createOrganizationAction` reales. Verificado con datos reales.

### Visibilidad de billing — decisión explícita
RLS de `organization_subscriptions` restringida a `company_owner`/`company_admin` — `manager` no ve términos comerciales. Verificado con datos reales.

### Test suite persistida
`tests/rls/phase14-subscriptions-tests.sql` — 9 bloques, corridos completos desde el archivo guardado, ~20 aserciones PASS.

### Lo que sigue explícitamente diferido — no fabricado
- Dashboard comercial de KCC Control Center — no construido.
- Página standalone de gestión de planes (`/subscription-plans`) — RPCs listas, sin UI dedicada.
- UI de gestión de entitlements por plan — backend real, sin pantalla de edición.
- `CommercialSection` no expone price override/custom terms/grace period desde UI (RPCs existen).
- Scheduler durable de recordatorios de trial (7/3/1 días) — no implementado.
- Tests de recipiente real de notificación para eventos de suscripción — no verificados en este cierre.
- Semántica de metadata de archive/reactivate — no decidida explícitamente.

### Verificación final de este cierre
TypeScript limpio. Vitest 34/34 PASS. Build de producción exitoso.

---

## Cierre verdaderamente final — 6 gaps reales corregidos, más un bug encontrado en mi propia corrección anterior

### 1. Entitlements ahora fail-closed (bug real de seguridad)
`organization_has_module_access()` usaba `coalesce(v_entitlement, true)` — sin fila explícita, el módulo quedaba **permitido**. Un módulo nuevo del producto se volvía disponible automáticamente para todos los planes existentes sin autorización de KCC. Corregido a fail-closed real: `enabled=true`→permitido, `enabled=false` **o sin fila**→denegado. Sembrados explícitamente los 6 módulos core (`work_orders`, `service_requests`, `estimates`, `tracking`, `warranty`, `communications`) para todos los planes activos existentes, para que el cambio de default no le quite acceso a nadie que ya lo tenía. `kcc_admin` conserva su bypass. `customers`/`vessels` quedan documentados explícitamente como datos base del producto, nunca toggleable por plan — decisión de producto, no omisión. Verificado con datos reales: `true` permite, `false` bloquea, sin fila bloquea, `kcc_admin` bypass, cambio de plan recalcula el entitlement inmediatamente (**entitlements son LIVE del plan actual, nunca snapshoteados** — a diferencia del precio, que sí se congela).

### 2. Enforcement de módulo expandido más allá de `tracking`
Conectado a `create_draft_estimate()` (módulo `estimates`), la policy de INSERT de `service_requests` (módulo `service_requests`), y `activate_warranty()` (módulo `warranty`). Verificado con datos reales: un plan sin `estimates` habilitado bloquea la creación de un estimate nuevo.

### 3. Semántica de metadata archive/reactivate — decisión explícita tomada
`reactivate_organization()` ahora limpia `archived_at`/`archived_by`/`archive_reason` en los campos actuales — una compañía reactivada nunca se ve "todavía archivada". La evidencia histórica completa queda preservada en `audit_events.before` (nunca se pierde). Reactivación **nunca** revive una suscripción cancelada — verificado con datos reales que tras archivar (que cancela la suscripción) y reactivar, la suscripción sigue `cancelled`, requiere una acción comercial explícita separada.

### 4. Leads del sitio web nunca se pierden por restricción comercial
`convert_website_lead()` ahora chequea `organization_has_active_access()` después de resolver el routing pero antes de crear cualquier registro operacional. El lead en sí ya es durable desde que llega — el chequeo solo bloquea la **conversión**, nunca borra ni descarta el lead. Nuevo estado `conversion_status='blocked_commercial'`, distinto de `'failed'` genérico, para que un reintento futuro sea identificable como "esperando que la compañía recupere acceso". Verificado con datos reales: lead bloqueado y preservado sin crear ningún `service_request`, y reintento exitoso automático tras restaurar el acceso de la organización.

### 5. Notificaciones de billing restringidas a decision-makers reales
Nueva estrategia de destinatario `billing_admin` (solo `company_owner`/`company_admin`, nunca `manager` ni `technician`) — coherente con la restricción de RLS ya aplicada en el cierre anterior. Las 7 reglas de notificación de suscripción migradas de `org_staff` a `billing_admin`.

### 6. Bug real encontrado en mi propia corrección anterior — worth documenting honestly
Al verificar el punto 5 con datos reales (nunca confiando en que "no hubo error" significa que funcionó), encontré que la migración anterior que introducía `billing_admin` había **fallado silenciosamente en su forma original** — el `ALTER TABLE` del constraint necesario venía después en la misma transacción que la función, así que cuando el constraint faltante causó un error, **toda la transacción se revirtió, incluida la función** — dejando `resolve_notification_recipients()` sin la rama `billing_admin` real, pese a que una migración posterior sí había aplicado el constraint y el `UPDATE` de las reglas por separado, dando la falsa impresión de que todo estaba aplicado. Detectado ejecutando `resolve_notification_recipients('billing_admin', ...)` directamente y viendo que devolvía vacío pese a que la fila de membresía sí existía. Corregido con una migración nueva que solo recrea la función. Verificado de punta a punta con datos reales: el owner recibe la notificación real, el manager queda excluido.

### Test suite ampliada y persistida
`tests/rls/phase14-subscriptions-tests.sql` ampliado con los bloques J (entitlements fail-closed), K (archive/reactivate metadata), L (protección de leads), M (notificaciones de billing) — 12 aserciones nuevas, todas corridas de punta a punta desde el contenido exacto que quedó guardado en el archivo, no solo escritas. En el camino corregí un bug en mi propia aserción de test (`test_reactivation_does_not_revive_subscription` tenía la comparación invertida) — detectado por el propio resultado inesperado, nunca ignorado.

### Lo que sigue explícitamente diferido — no fabricado
- **Página standalone `/subscription-plans`** — las RPCs (`create_subscription_plan`, `update_subscription_plan`) existen y están probadas; no hay UI dedicada de gestión de planes ni de entitlements todavía.
- **`CommercialSection` no expone**: price override explícito, custom terms, controles de grace period (las RPCs `grant_subscription_grace_period`/`end_subscription_grace_period` existen y están probadas, sin botón en la UI), billing cycle editable después de la creación inicial.
- **Dashboard comercial de KCC Control Center** — no construido.
- **Scheduler durable de recordatorios de trial** (7/3/1 días, evento `SUBSCRIPTION_TRIAL_EXPIRED` emitido exactamente una vez de forma programada) — no implementado. La corrección de estado efectivo sigue siendo la autoridad real sin cron, pero ningún proceso dispara las notificaciones de recordatorio todavía.

### Verificación final de este cierre verdaderamente final
TypeScript limpio (mismo error preexistente de Phase 2). Vitest 34/34 PASS (sin cambios — todos los fixes de este cierre fueron de base de datos). Build de producción exitoso. Regresión puntual confirmada: creación de work order + estimate con todas las entitlements configuradas sigue funcionando normalmente.

---

## Cierre absoluto final — infraestructura crítica corregida, 2 bugs reales más encontrados

### 1. Bug real de replay limpio corregido
La migración 245 original hacía el `UPDATE` de `notification_rules` **antes** de que 246 extendiera el `CHECK` constraint que permite `'billing_admin'` — en una base limpia, 245 habría fallado. Reescrita para ser autocontenida (constraint → función completa → UPDATE, en el orden correcto), con 246 y 247 convertidas en no-ops idempotentes (mismo contenido final, seguro re-aplicarlas). Verificado re-aplicando el contenido de 245 sobre el estado ya correcto sin error, y confirmando las 7 reglas de facturación en `billing_admin`.

### 2. Creación atómica de plan + entitlements
`create_subscription_plan_with_entitlements()` — crea el plan y sus módulos iniciales en una sola transacción, reusando `create_subscription_plan()` tal cual existe. `set_plan_module_entitlement()` — RPC trusted para alternar un módulo de un plan existente, auditado. Verificado con datos reales: plan nuevo con módulos seleccionados funciona de inmediato, módulo omitido queda denegado (fail-closed), el toggle afecta a organizaciones ya suscritas al plan de forma inmediata (entitlements son **live**, nunca snapshoteados — decisión ya documentada en el cierre anterior).

### 3. Reintento automático de leads bloqueados — implementado, no solo documentado
`retry_commercially_blocked_leads(organization_id, batch_size)` — bounded (máx. 100), solo leads de esa organización con `blocked_commercial`, reusa `convert_website_lead()` idempotente, un lead que vuelve a fallar nunca bloquea a los demás. **Conectado automáticamente** a `assign_organization_subscription()` — activar una suscripción real reintenta los leads bloqueados de esa organización sin intervención manual. Verificado con datos reales: lead bloqueado se convierte automáticamente al activar la suscripción, lead de otra organización queda intacto, `batch_size` fuera de rango (1-100) rechazado. La documentación ahora dice correctamente "reintentado automáticamente tras eventos comerciales confiables", no solo "reintentable".

### 4. Scheduler durable de trial — real, wireado, y con un bug crítico encontrado y corregido
`subscription_lifecycle_milestones` (tabla con `unique(subscription_id, milestone)` — idempotencia real, nunca duplica un recordatorio) + `process_due_subscription_lifecycle_milestones()`. Verificado con datos reales: 4 milestones (7d/3d/1d/expired) creados al iniciar un trial con fechas derivadas de `trial_ends_at` real; correr el procesador dos veces sobre el mismo milestone vencido emite `SUBSCRIPTION_TRIAL_EXPIRED` **exactamente una vez** y genera **exactamente una** notificación.

**`pg_cron` está genuinamente disponible en este proyecto Supabase** — instalado y con el job `process-subscription-lifecycle-milestones` programado cada hora, confirmado `active=true` consultando `cron.job` directamente. Esto no es infraestructura "lista para activar" — es un job real y corriendo.

**Bug crítico real encontrado en el camino**: `process_due_subscription_lifecycle_milestones()` exigía `is_kcc_admin() OR is_platform_trusted_actor()`, ambas dependientes de claims JWT que **nunca existen** cuando `pg_cron` invoca una función (corre sin contexto HTTP). El job programado habría fallado silenciosamente cada hora en producción real — nunca lo asumí solo porque `cron.schedule()` no dio error; lo verifiqué ejecutando la función directamente sin contexto JWT, replicando el entorno real de `pg_cron`, y ahí encontré la falla real. Corregido: ausencia **total** de contexto JWT (nunca un actor equivocado, sino ningún actor) se trata como invocación interna de plataforma confiable. Reverificado: funciona sin JWT (contexto cron real), sigue rechazando a un actor incorrecto que sí presenta un JWT.

### Test suite ampliada
Las nuevas RPCs (fail-closed atómico, reintento de leads, milestones) fueron verificadas extensamente con datos reales en esta sesión — no llegué a persistir estos bloques nuevos en `tests/rls/phase14-subscriptions-tests.sql` antes de agotar el tiempo de esta pasada; quedan como verificación de sesión, documentada aquí con el detalle exacto de cada aserción corrida, pero no como archivo ejecutable todavía.

### Lo que sigue explícitamente sin construir — no fabricado
Dado el alcance real de esta pasada, las siguientes piezas de UI **no se completaron**:
- **`/subscription-plans`** — página standalone de gestión de planes. Las RPCs (`create_subscription_plan_with_entitlements`, `update_subscription_plan`, `set_plan_module_entitlement`) existen, probadas, sin UI dedicada.
- **UI de gestión de entitlements** dentro de esa página — mismo estado: backend real, sin pantalla.
- **`CommercialSection` sigue sin exponer**: price override explícito, custom terms, controles de grace period (RPCs existen y probadas desde el cierre anterior), billing cycle editable post-creación.
- **Dashboard comercial de KCC Control Center** — no construido.
- **Persistencia de los nuevos bloques de test** en el archivo `.sql` — verificados en sesión, no en archivo ejecutable todavía.

### Verificación final de este cierre absoluto
TypeScript limpio. Vitest 34/34 PASS. Build de producción exitoso. Todas las RPCs nuevas de esta pasada verificadas con datos reales, incluidos dos bugs genuinos encontrados y corregidos (orden de replay de migración, y autoridad de `pg_cron` sin contexto JWT) — ninguno de los dos habría aparecido sin ejecutar las verificaciones exactas que se corrieron.

---

## Cierre de UI — las 4 piezas de producto diferidas, completadas

### 1. `/subscription-plans` — página real de KCC Admin
Crear plan (con selección de módulos incluidos — nunca se crea un plan público sin entitlements explícitos, ver punto siguiente), editar precios por ciclo, archivar (nunca hard-delete), y gestión de entitlements con toggles reales que llaman a `set_plan_module_entitlement()` — el efecto es inmediato para toda organización ya suscrita a ese plan (entitlements son live, decisión ya documentada). Cada plan muestra cuántas organizaciones lo tienen activo. Usa exclusivamente las RPCs trusted ya existentes — ninguna lógica de negocio duplicada en el cliente.

### 2. Entitlements — creación atómica reforzada en la UI
El formulario de creación de plan exige seleccionar módulos ANTES de crear — nunca se puede enviar un plan sin haber decidido explícitamente qué incluye, reforzando en la UI lo que `create_subscription_plan_with_entitlements()` ya garantiza a nivel de transacción.

### 3. `CommercialSection` — controles completos
Agregados: price override (con aclaración explícita de que nunca edita el catálogo, solo el precio negociado de esa compañía), custom terms, y la sección completa de grace period (otorgar con días+razón, terminar manualmente) — conectados a `grant_subscription_grace_period()`/`end_subscription_grace_period()`, ya probadas en el cierre anterior. El display ahora distingue explícitamente "Negotiated price" (el snapshot real de esa compañía) de cualquier precio de catálogo, y muestra el grace period vigente con su fecha de fin y la aclaración de que no fue causado por ningún proveedor de pago (Phase 14 no cobra).

### 4. Dashboard comercial (`/commercial-dashboard`)
Conteos reales por estado efectivo (trials activos, expirando pronto con deep-link a cada compañía, expirados, activos, grace period, past due, cancelados, complimentary, archivados), distribución de planes, y **valor recurrente contratado normalizado por semana** con fórmula documentada y determinística (mensual ÷ 4.345, anual ÷ 52.14 — nunca una suma cruda de precios de ciclos distintos). Excluye explícitamente complimentary/cancelled/archived/trialing del total contratado — nunca se etiqueta como "revenue" o "collected", siempre "contracted recurring value (equivalent)".

### Bug real de build encontrado y corregido en el camino
Al correr el build de producción por primera vez con la nueva UI, falló: `PlanRow.tsx` (componente cliente) importaba `CORE_MODULE_KEYS` y el tipo `PlanManagementRow` desde `lib/subscription-plans/data.ts`, un archivo marcado `import 'server-only'` — Next.js rechaza esto en build real (aunque `next dev` a veces lo deja pasar silenciosamente). Corregido moviendo la constante y el tipo a `lib/subscription-plans/shared.ts`, sin la marca `server-only`, y actualizando los imports de los componentes cliente. Reconfirmado: build de producción exitoso.

### Regresión final
Flujo completo (plan con las 6 entitlements core habilitadas → suscripción → customer → vessel → work order → estimate) corrido de punta a punta con datos reales — confirma que el sistema de entitlements fail-closed, una vez configurado correctamente, no interfiere con el flujo operacional normal.

### Verificación final absoluta
TypeScript limpio (mismo error preexistente de Phase 2). Vitest 34/34 PASS. **Build de producción exitoso** (tras el fix de `server-only`). Regresión de flujo completo con datos reales: PASS.

### Lo que sigue sin cubrir
- Persistencia como archivo `.sql` ejecutable de la verificación de este último tramo de UI (quedó como verificación de sesión — no hay assertions SQL nuevas que agregar aquí ya que este tramo fue mayormente frontend, pero el flujo de regresión de punta a punta no está en el archivo de tests todavía).
- `lint` no se corrió en esta pasada (dado que en cierres anteriores de Phase 13 se documentó que `next lint` no corre de forma no interactiva en este repo — misma condición preexistente).

---

## Estado final autoritativo — pase de consistencia del lifecycle scheduler

Esta sección reemplaza cualquier nota de "diferido" anterior sobre el scheduler que haya quedado contradicha por lo implementado aquí.

### Bugs reales corregidos (todos verificados con datos reales)

1. **Trials cortos con recordatorios imposibles**: `schedule_trial_milestones()` creaba los 4 milestones sin importar la duración real — un trial de 2 días generaba recordatorios de "7 días restantes" ya vencidos al crearse. Corregido: cada milestone solo se programa si su fecha es realmente futura. `trial_expired` siempre se programa. Verificado: trial de 2 días → solo `trial_1d` + `trial_expired`.

2. **Extender un trial nunca reprogramaba el scheduler**: `extend_organization_trial()` actualizaba `trial_ends_at` pero dejaba los milestones apuntando a la fecha vieja. Nueva función `reschedule_trial_milestones()`: realinea lo no procesado (crea `7d`/`3d` que antes no eran elegibles si el trial se alargó lo suficiente); un milestone ya entregado nunca se reenvía; `trial_expired` siempre se realinea y se reabre si ya había disparado. Verificado con extensión real de 2→20 días.

3. **Grace period nunca se programaba de verdad**: `grant_subscription_grace_period()` no creaba el milestone `grace_expired`. Corregido con reprogramación segura (nunca duplica), y `end_subscription_grace_period()` marca el milestone pendiente como atendido sin emitir el evento — nunca un `SUBSCRIPTION_GRACE_PERIOD_EXPIRED` fantasma. **7/7 tests PASS.**

4. **Cancelación al fin de período — nunca se programaba, y su semántica era falsa**: emitía `SUBSCRIPTION_CANCELLED` de inmediato pese a que el acceso seguía activo. Corregido: emite `SUBSCRIPTION_CANCELLATION_SCHEDULED`, programa el milestone real, y solo el procesador emite `CANCELLED` al llegar la fecha. Cancelación inmediata sigue funcionando igual. **6/6 tests PASS.**

5. **El procesador ahora persiste el status almacenado**: `grace_expired`→`past_due`; `scheduled_cancellation`→`cancelled`+`cancelled_at`. La autoridad de acceso sigue siendo exclusivamente `subscription_effective_status()`, nunca dependiente de cron — esto solo evita que el status visible en UI/KCC quede desalineado.

6. **Bug real encontrado verificando el flujo más común**: el reintento automático de leads bloqueados solo estaba conectado a `assign_organization_subscription()` (KCC), no al flujo real más frecuente (`select_organization_plan()`, auto-servicio). Al conectarlo apareció un segundo bug: `retry_commercially_blocked_leads()` exigía autoridad de `kcc_admin`, pero la llamada interna corre con el JWT real del `company_owner` y se rechazaba a sí misma. Corregido agregando `is_org_staff()` como autoridad válida. Verificado de punta a punta: trial vencido con lead bloqueado → owner selecciona plan → lead se convierte automáticamente.

7. **`pg_cron` confirmado idempotente**: re-programar el mismo job actualiza en vez de duplicar — verificado (`count(*)=1` antes y después).

8. **UI de gestión de planes completada**: agregada edición de trial_default_days (backend no lo soportaba), name/description/status/público-privado ya expuestos junto a precios.

9. **Dashboard**: distribución de planes desglosada por estado efectivo real, nunca un conteo plano que mezcla trials/activos/cancelados.

### Test suite persistida y reverificada
`tests/rls/phase14-subscriptions-tests.sql` — bloque R agregado (trials cortos, reprogramación, grace completo, cancelación programada, reintento vía auto-servicio). Corrido de punta a punta desde el contenido exacto guardado en el archivo — reconfirmado PASS en esta sesión.

### Verificación final
TypeScript limpio (mismo error preexistente de Phase 2). Vitest **34/34 PASS**. Build de producción **exitoso**. `lint` sigue sin poder correr de forma no interactiva (condición preexistente desde Phase 13).
