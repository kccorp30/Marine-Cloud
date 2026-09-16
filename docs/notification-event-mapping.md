# Notification Event Mapping — Phase 3B

Documentado, no implementado — Phase 3B no construye el sistema de notificaciones (eso sigue siendo Phase 9). Esto confirma que los eventos ya existentes alcanzan para ese trabajo futuro, sin tener que cambiar ni renombrar nada retroactivamente.

## Eventos ya emitidos que van a alimentar las notificaciones futuras

| Notificación futura | `domain_events.event_type` que ya se emite | Emitido desde |
|---|---|---|
| Technician assigned | `TECHNICIAN_ASSIGNED` | Trigger sobre `assignments` (Phase 1) |
| Technician en route | `TECHNICIAN_EN_ROUTE` | `technician_start_route()` (Phase 2) |
| Technician arrived | `TECHNICIAN_CHECKED_IN` | `technician_check_in()` (Phase 2) |
| Work started | `TECHNICIAN_WORK_STARTED` | `start_time_entry()` cuando `entry_type='work'` (Phase 2) |
| Customer action required | `WORK_ORDER_STATUS_CHANGED` con `to_status` en (`awaiting_approval`, `waiting_customer_approval`) | `transition_work_order()` (Phase 1) — el `payload` ya trae `to_status`, la regla de notificación futura solo necesita filtrar por esos dos valores, no un evento nuevo |
| Work completed | `WORK_ORDER_STATUS_CHANGED` con `to_status = 'completed'` | `transition_work_order()` (Phase 1) — mismo evento, mismo filtro por `payload.to_status` |

**No se duplicó ningún evento.** "Customer action required" y "Work completed" no necesitan un tipo de evento nuevo — ya viven como casos particulares de `WORK_ORDER_STATUS_CHANGED`, distinguibles por el `to_status` que ya va en el `payload`. Cuando se construya Phase 9, la tabla `notification_rules` (ya prevista en `docs/notification-architecture-plan.md` de Phase 2) solo necesita reglas tipo `event_type = 'WORK_ORDER_STATUS_CHANGED' AND payload->>'to_status' = 'awaiting_approval'`, no un cambio de código acá.

## Por qué esto ya es suficiente

`work_order_id` (Phase 3A/3B) + `organization_id` (desde Phase 0) están en cada fila de `domain_events` — son exactamente los dos datos que una regla de notificación futura necesita para saber **a quién** avisar (miembros de esa organización, o el customer de ese work order específico) sin tener que volver a tocar ninguno de los emisores de eventos ya construidos.
