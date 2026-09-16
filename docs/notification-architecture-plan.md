# Notification & Alert Architecture — Implementado en Phase 9

**Estado: implementado.** Este documento describía la arquitectura antes de construirse (Phase 2). Phase 9 la implementó siguiendo exactamente este plan — ningún evento de `domain_events` se renombró ni se tocó. Ver `docs/phase9-implementation-report.md` para el detalle completo de lo construido, RLS, tests, y limitaciones.


## Modelo de severidad

| Severidad | Ejemplos | Comportamiento |
|---|---|---|
| `INFO` | foto subida, nota agregada, update de work order | Centro de notificaciones + badge si no leído, sin sonido disruptivo |
| `ACTION_REQUIRED` | aprobación de customer/manager, asignación de técnico, factura pendiente | Alerta in-app + push + sonido corto + badge |
| `URGENT` | solicitud de asistencia KCC, bloqueo grave reportado, problema urgente de scheduling | Sonido distintivo + vibración + banner prominente + push + contador + estado de acknowledgement |
| `CRITICAL` | (reservado a futuro) alerta de seguridad del vessel, alarma IoT crítica, asistencia de emergencia | Comportamiento de atención más fuerte + acknowledgement obligatorio — usar con moderación extrema |

## Alerta de KCC Assistance (la más importante, según el brief)

Campos mínimos que va a necesitar la tabla futura:
`requesting_technician_id, organization_id, vessel_id, work_order_id, current_job_status, reason/category, urgency, notes, created_at, acknowledgement_status, accepted_by, accepted_at`.

Acciones que KCC Admin va a necesitar: OPEN REQUEST, ACCEPT ASSISTANCE, JOIN/START ASSISTANCE, mark resolved/escalated. Al aceptar, el técnico recibe confirmación ("KCC accepted your assistance request"). Esta interacción alimenta `domain_events`, historial de notificaciones, KCC Assistance Ledger (Phase 6), y el timeline del work order (Phase 3) — cuatro consumidores del mismo evento, otra razón para que el evento se emita una sola vez, en un solo lugar.

## Diseño de sonido

IDs de sonido configurables (no hardcodeados en componentes): `notification_info`, `action_required`, `kcc_assistance_request`, `urgent`, `critical`. Un servicio centralizado de audio/notificaciones (todavía no existe) será el único lugar que reproduce sonido — ningún componente individual debe tocar audio directamente. Debe respetar: mute del usuario, permiso de notificación del navegador/dispositivo, horas silenciosas configuradas, preferencias de accesibilidad.

## Notification Center — esquema futuro

Cada notificación: `recipient, organization_id, event_type, severity, title, body, related_entity_type, related_entity_id, read_at, acknowledged_at, delivery_channels[], delivery_status, created_at`.

Canales: `in_app, push, whatsapp, email, sms` (futuro) — no implementar todos de una — empezar con `in_app`.

## Por qué Phase 2 ya es compatible con esto, sin cambios

Los `domain_events` de Phase 2 (`TECHNICIAN_EN_ROUTE`, `TECHNICIAN_CHECKED_IN`, `MEDIA_ADDED`, `MEASUREMENT_RECORDED`, etc.) ya tienen exactamente la forma que una futura tabla de `notification_rules` necesita para mapear `event_type → severity`: un `event_type` string estable, `organization_id`, `entity_type`/`entity_id`, y `payload` jsonb con contexto. Cuando llegue Phase 9, la implementación es: crear `notification_rules` (event_type → severity + destinatarios) y una función/trigger que, al insertarse un `domain_event`, calcule notificaciones — **sin tocar ni renombrar ningún evento ya emitido**. Esta es la única razón por la que valía la pena escribir este documento ahora: confirmar que no hace falta ningún cambio retroactivo.

## Qué se implementó en Phase 9

`notifications`, `notification_rules`, el motor (trigger sobre `domain_events`), Notification Center, la campanita con badge/realtime, KCC Assistance completo (schema, workflow, UI técnico + consola admin), y un servicio de sonido mínimo. Detalle completo en `docs/phase9-implementation-report.md`. Push/WhatsApp/email/SMS siguen sin implementar — arquitectura preparada, no construida.

