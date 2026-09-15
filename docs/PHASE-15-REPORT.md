# Phase 15 — Platform Billing, Manual Payments & Revenue Ledger

## Alcance de esta pasada — honesto desde el inicio
Dado el tamaño real del brief (77 secciones), esta pasada construyó y verificó con datos reales el **motor financiero central** — schema, RLS, y el ciclo de vida completo de pago (generar cargo → registrar pago → verificar → auto-asignar → restaurar acceso). La UI (página de billing de company, operaciones de KCC, dashboard financiero, recibos) y varias piezas secundarias (void de charge, reconciliación como job programado, integración real de ePayco) **no se completaron** — documentadas explícitamente abajo, nunca fabricadas.

## Separación de dominio financiero (nunca mezclado)
`platform_billing_charges`/`platform_payments`/etc. son el dominio **KCC↔company**. Los `invoices`/`payments` existentes desde Phase 7 son **company↔boat customer** — dominios completamente distintos, ninguna tabla ni RPC compartida.

## Deuda ≠ Pago (principio central)
`platform_billing_charges` (lo que se debe) y `platform_payments` (lo que se recibió) son objetos separados desde el diseño — nunca un campo genérico `payment_amount`. `platform_payment_allocations` conecta ambos, permitiendo pagos parciales, un pago cubriendo varios cargos, o varios pagos cubriendo un cargo.

## Schema
- **`platform_billing_charges`**: NUMERIC para todo el dinero. Constraint real `unique(subscription_id, billing_period_start, billing_period_end)` — la idempotencia de generación de billing es una garantía de base de datos, no solo de aplicación.
- **`platform_payment_methods`**: configurable, sembrado con Zelle/Cash/Bank Transfer/Nequi/Other — KCC puede agregar más sin cambiar código.
- **`platform_payments`**: `provider` preparado para `manual`/`epayco`/`stripe`, pero solo `manual` tiene lógica real implementada en esta fase.
- **`platform_payment_evidence`**: reusa el mismo patrón de storage seguro del resto del proyecto — nunca un bucket público.
- **`platform_payment_allocations`**: la única forma real de mover dinero de un pago a un cargo.
- **`platform_ledger_entries`**: append-only real — ninguna RPC de esta fase actualiza una fila de ledger existente, solo inserta. Documentado explícitamente como ledger **operacional**, nunca contabilidad formal de doble entrada.

## Autoridad de precio — verificado con datos reales
`generate_platform_charge()` usa `organization_subscriptions.price_snapshot` (Phase 14), **nunca** el precio actual del catálogo. Verificado: cambié el precio del plan después de emitir un cargo y confirmé que el cargo ya emitido no cambió.

## No se factura complimentary ni trial — verificado
`generate_platform_charge()` rechaza explícitamente suscripciones `complimentary` y `trialing`. Verificado con datos reales (ambos casos lanzan excepción real).

## Idempotencia real de generación — verificado
El `unique index` en `(subscription_id, billing_period_start, billing_period_end)` hace que un reintento de `generate_platform_charge()` para el mismo período devuelva el cargo existente en vez de duplicar. Verificado con datos reales.

## Política de fecha de vencimiento — decisión explícita
`due_at = billing_period_start` (pago por adelantado) — regla global única para weekly/monthly/annual/custom, documentada acá porque el brief pedía explícitamente no inventar la política sin documentarla.

## Estado efectivo de un cargo — nunca depende de que la columna esté fresca
`calculate_charge_effective_status()` (mismo patrón que `warranty_effective_status()`/`subscription_effective_status()` de fases anteriores): deriva `paid`/`partially_paid`/`overdue`/`open`/`void` desde `balance_due`/`amount_paid`/`due_at` en tiempo real, nunca confía en que el status guardado esté actualizado.

## `organization_billing_is_current()` — la única función que decide "¿está al día?"
Nunca se inspeccionan pagos/cargos ad hoc en cada componente — todo pasa por esta función central.

## Ciclo de vida de pago — verificado de punta a punta con datos reales
1. `record_manual_platform_payment()` (KCC) / `submit_platform_payment_proof()` (company) — **siempre** `pending_verification`, la company nunca puede auto-verificar su propio pago, ni siquiera indirectamente.
2. `verify_platform_payment()` (solo KCC) — al verificar, **auto-asigna** al cargo abierto más antiguo de la misma moneda hasta agotar el pago (regla determinística: "oldest due first"). El remanente sin asignar queda visible, nunca se inventa un refund.
3. `reject_platform_payment()` / `reverse_platform_payment()` — solo KCC, razón obligatoria, auditado. La reversa **recalcula** el status de cada cargo afectado desde cero (nunca resta a mano) — un cargo `paid` puede volver a `open`/`overdue` automáticamente.

**Verificado con datos reales, flujo completo**: cargo overdue real → pago Cash registrado → verificado → auto-asignado → cargo pasa a `paid` → suscripción `past_due` pasa a `active` → lead bloqueado de esa organización se reintenta automáticamente. Todo en una sola cadena de RPCs reales, sin intervención manual de base de datos.

## Restauración de acceso — reglas de seguridad verificadas
`reconcile_organization_platform_billing()`: termina `grace_period`/`past_due` cuando el balance real queda al día, y reintenta leads bloqueados. **Verificado con datos reales que una organización archivada NUNCA se reactiva** por esta función, sin importar cuánto pague — exige la reactivación explícita de KCC ya existente desde Phase 14. Una suscripción `cancelled` tampoco se revive — pagar deuda histórica nunca implica una activación nueva.

## Bug real preexistente encontrado y corregido en el camino
Al verificar Phase 15 con llamadas SQL directas, encontré que `update_subscription_plan()` (Phase 14, migración 259) tenía **dos versiones simultáneas** en la base — la migración original usó `create or replace function` con una firma de 9 parámetros distinta a la de 8 parámetros ya existente, y Postgres **creó una segunda sobrecarga** en vez de reemplazar la función, porque la lista de tipos de argumento era diferente. Esto causaba ambigüedad real en cualquier llamada que no coincidiera exactamente con una de las dos firmas. Corregido eliminando la versión vieja de 8 parámetros. Nunca hubiera aparecido sin intentar llamar la función directamente con datos reales.

## RLS — verificado
Solo `company_owner`/`company_admin` leen las tablas de billing de su propia organización (misma decisión ya tomada en Phase 14 para suscripciones — dato financiero sensible). El ledger es **interno de KCC exclusivamente**, ni siquiera el owner de la company lo ve. Ninguna mutación directa — todo vía RPCs `SECURITY DEFINER`.

## Diferido explícitamente — no fabricado
- **Página de billing de company** (`/billing`) ampliada con cargos/pagos/balance/envío de comprobante — la página actual de Phase 14 solo muestra la suscripción, no los cargos ni pagos de esta fase.
- **UI de operaciones de billing de KCC** (cola de verificación, entrada manual, alocación, cola de vencidos) — solo las RPCs existen, sin pantalla.
- **Dashboard financiero de KCC** — no construido.
- **`void_platform_charge()`** — no implementado en esta pasada.
- **Vista de recibo imprimible** — no construida.
- **Scheduler de generación automática de cargos** (`generate_platform_billing_charges()` corriendo periódicamente) — la RPC de generación individual existe y es idempotente, pero no hay un job de `pg_cron` que la invoque automáticamente para todas las suscripciones activas todavía.
- **Recordatorios de pago** (due soon/due today/overdue) vía milestones — no implementado.
- **`reconcile_platform_billing()` como job de reparación separado** — la reconciliación ocurre como efecto inmediato de `verify_platform_payment()`, pero no existe todavía un job periódico aparte que capture casos donde ese efecto inmediato falló.
- **Integración real de ePayco** — ni siquiera la interfaz `PaymentProvider` abstracta se construyó todavía; el `provider` de las tablas soporta el valor `epayco` a nivel de schema, nada más.
- **Comisión KCC conectada al ledger** (Phase 10 → Phase 15) — no implementado.
- **Ingresos de Assistance conectados al ledger** — no implementado.
- **Test suite persistida en `.sql`** — todo lo verificado en esta pasada fue verificación de sesión con datos reales (documentada en detalle arriba), no un archivo `tests/rls/phase15-*.sql` ejecutable todavía.

## Verificación de esta pasada
TypeScript/vitest/build no se tocaron con cambios de UI en esta pasada (sin archivos `.tsx`/`.ts` nuevos) — deberían seguir en el mismo estado que el cierre de Phase 14. 8/8 aserciones SQL clave verificadas con datos reales en sesión, cubriendo generación de cargo, idempotencia, precio congelado, no-billing de complimentary/trial, ciclo completo de pago con auto-asignación, pago parcial, reversa, y seguridad de organización archivada.
