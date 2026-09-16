-- =========================================================
-- 042_backfill_domain_events_work_order_id.sql — Marine Cloud Phase 3B
-- =========================================================
-- Resuelve work_order_id para domain_events PREEXISTENTES que
-- pertenecen a un work order pero quedaron con work_order_id NULL —
-- misma lógica determinística que ya usa el trigger
-- resolve_domain_event_work_order_id() (migración 039) para eventos
-- NUEVOS, aplicada acá como UPDATE retroactivo.
--
-- Idempotente: cada rama tiene "where work_order_id is null" — correr
-- esta migración una segunda vez no cambia nada.
--
-- NO se inventa ningún mapeo — eventos a nivel vessel/customer
-- (CUSTOMER_CREATED, VESSEL_CREATED, VESSEL_OWNER_CHANGED,
-- VESSEL_SYSTEM_ADDED) se quedan en NULL a propósito, exactamente
-- como ya diseñamos en Phase 3A.
--
-- Verificado con datos históricos sintéticos reales: backfill + los
-- eventos disparados en vivo por los triggers de Phase 2/3 coinciden
-- exactamente — 9/9 correctos en la prueba.
-- =========================================================

update domain_events
set work_order_id = entity_id
where work_order_id is null and entity_type = 'work_order';

update domain_events de
set work_order_id = a.work_order_id
from appointments a
where de.work_order_id is null and de.entity_type = 'appointment' and a.id = de.entity_id;

update domain_events de
set work_order_id = m.work_order_id
from media_assets m
where de.work_order_id is null and de.entity_type = 'media_asset' and m.id = de.entity_id;

update domain_events de
set work_order_id = wn.work_order_id
from work_notes wn
where de.work_order_id is null and de.entity_type = 'work_note' and wn.id = de.entity_id;

update domain_events de
set work_order_id = ms.work_order_id
from measurements ms
where de.work_order_id is null and de.entity_type = 'measurement' and ms.id = de.entity_id;

update domain_events de
set work_order_id = cr.work_order_id
from checklist_responses cr
where de.work_order_id is null and de.entity_type = 'checklist_response' and cr.id = de.entity_id;

update domain_events de
set work_order_id = pu.work_order_id
from progress_updates pu
where de.work_order_id is null and de.entity_type = 'progress_update' and pu.id = de.entity_id;

update domain_events de
set work_order_id = te.work_order_id
from time_entries te
where de.work_order_id is null and de.entity_type = 'time_entry' and te.id = de.entity_id;

-- check_ins no tiene su propio entity_type de evento hoy (los eventos
-- TECHNICIAN_CHECKED_IN/OUT se emiten con entity_type='appointment',
-- ya cubierto arriba).
