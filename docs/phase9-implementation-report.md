# Phase 9 — Notifications, Alerts & KCC Assistance — Implementation Report

## Schema (migraciones 123–133)
- `notifications` — RLS: solo el destinatario (o kcc_admin) puede leer. Ninguna mutación directa — solo vía `mark_notification_read`/`mark_all_notifications_read`/`acknowledge_notification`. Deduplicación real vía índice único `(source_domain_event_id, recipient_user_id, source_rule_id)`.
- `notification_rules` — mapea `domain_events.event_type` (+ `payload_filter` opcional vía containment jsonb) a severidad/destinatario/plantilla. `organization_id` nulo = regla de plataforma. Nunca un motor de "ejecutar JSON arbitrario" — `recipient_strategy` es un enum cerrado (`org_staff`, `assigned_technician`, `customer`, `kcc_admin`, `requesting_technician`).
- `kcc_assistance_requests` — máquina de estados explícita (`open→accepted→started→resolved`, `escalated` alcanzable desde cualquiera de los tres primeros). Nunca `open→started` directo.

## Motor de notificaciones
**Elección de arquitectura: trigger de base de datos** (`AFTER INSERT` sobre `domain_events`), consistente con el patrón ya existente en el proyecto (`trg_domain_events_update_last_activity`, `trg_resolve_domain_event_wo` ya viven ahí). Nunca polling desde el browser. Fallos de notificación se atrapan dentro del trigger y nunca revierten la transacción de negocio original (`raise warning`, no `raise exception`).

## RLS
Todas las tablas nuevas: RLS habilitada desde el día uno, sin GRANT de mutación directa a `authenticated` — solo funciones `SECURITY DEFINER` con su propio chequeo de autorización. `generate_notifications_from_domain_event()`, `render_notification_text()`, `resolve_notification_recipients()` bloqueadas de invocación directa (solo las llama el trigger).

## Reglas de notificación implementadas (5 mínimas + 2 de KCC Assistance)
Mapeadas 1:1 a eventos **ya existentes** — ninguna `CUSTOMER_ACTION_REQUIRED` ni `WORK_COMPLETED` inventada:
- `TECHNICIAN_ASSIGNED` / `TECHNICIAN_EN_ROUTE` / `TECHNICIAN_CHECKED_IN` / `TECHNICIAN_WORK_STARTED` → customer, `info`
- `WORK_ORDER_STATUS_CHANGED` con `to_status` en (`awaiting_approval`, `waiting_customer_approval`) → customer, `action_required`
- `WORK_ORDER_STATUS_CHANGED` con `to_status = completed` → customer, `info`
- `KCC_ASSISTANCE_REQUESTED` → todo `kcc_admin`, `urgent`, `acknowledgement_required = true`
- `KCC_ASSISTANCE_ACCEPTED` → técnico que pidió la asistencia, `action_required`

## Eventos nuevos (KCC Assistance)
`KCC_ASSISTANCE_REQUESTED`, `KCC_ASSISTANCE_ACCEPTED`, `KCC_ASSISTANCE_STARTED`, `KCC_ASSISTANCE_RESOLVED`, `KCC_ASSISTANCE_ESCALATED` — inspeccionados los nombres existentes antes de crearlos, ninguno duplicado. Se integran al timeline del work order vía el mismo mecanismo de `domain_events` ya usado por el resto del proyecto — no se creó un timeline paralelo.

## UI
- Campanita en `AppNav` — badge de no-leídos, realtime (Supabase Realtime, tabla agregada a la publicación en la migración 133), flash visual al llegar una nueva
- `/notifications` — Notification Center, filtros (todas/no-leídas/acción requerida), deep links a work order/vessel/invoice/estimate (nunca inventa un link para un `related_entity_type` no soportado), marcar leído/reconocer
- `/kcc-assistance` — consola completa para `kcc_admin` (cola abierta + historial, acciones aceptar/iniciar/resolver/escalar) o historial propio para el técnico
- Botón "Request KCC Assistance" contextual en el detalle del work order, visible solo para el técnico asignado

## Sonido
Servicio centralizado (`lib/notifications/sound-service.ts`) — único lugar que reproduce audio, ningún componente toca audio directo. Respeta mute (localStorage). **Limitación honesta**: no hay archivos de audio reales en este entorno — genera tonos simples vía WebAudio, distintos por sonido (`notification_info`, `action_required`, `kcc_assistance_request`, `urgent`, `critical`). "Horas silenciosas" y preferencias de accesibilidad más allá del mute simple: no implementadas, documentado como diferido.

## Realtime
Supabase Realtime sobre `notifications`/`kcc_assistance_requests`. La campanita se suscribe a `INSERT` filtrado por `recipient_user_id`. El conteo inicial siempre se carga desde la base (autoritativa) en cada render del layout — nunca depende solo de realtime.

## Tests
`tests/rls/phase9-notifications-tests.sql` — **24/24 PASS**, corridos en vivo desde el archivo guardado: generación de notificaciones, idempotencia, `WORK_ORDER_STATUS_CHANGED`, aislamiento tenant, leer/reconocer, reglas, y el ciclo completo de KCC Assistance (solicitar, rechazar no-asignado, aceptar, rechazar no-KCC, rechazar transición ilegal, iniciar, resolver, escalar, notificación de aceptación al técnico).

## Regresión
Phase 3B, 4B, 5, 6, 7, 8, y `transition_work_order` — **7/7 PASS**.

## Bugs reales encontrados y corregidos durante la construcción
1. `request_kcc_assistance()` llamaba a `log_audit_event()` (exige `is_org_staff()`) pero quien la invoca es un técnico — corregido con `log_audit_event_internal()` (mismo patrón ya usado en Phase 6/7).
2. `generate_notifications_from_domain_event()` (la función del trigger) quedó ejecutable por `anon` vía RPC — cerrada por completo, nunca debería invocarse manualmente.

## Limitaciones conocidas / diferido
- Push, WhatsApp, email, SMS: **no implementados** — arquitectura preparada (`delivery_channels` soporta los valores, pero nunca reporta `delivered` para un canal sin proveedor real), Phase 9 es usable completamente solo con `in_app`
- Sonido: tonos generados, no archivos de audio de marca; sin "horas silenciosas"
- Sin infraestructura de preferencias de usuario más allá de mute simple
