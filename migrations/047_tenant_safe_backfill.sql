-- =========================================================
-- 047_tenant_safe_backfill.sql — Marine Cloud Phase 3B hardening
-- =========================================================
-- La migración 042 resolvía work_order_id por entity_id sin exigir
-- explícitamente que la organización de la entidad relacionada
-- coincidiera con domain_events.organization_id. En la práctica esto
-- nunca podía resolver mal (entity_id es una PK real), pero no había
-- defensa explícita contra un evento histórico con organization_id
-- inconsistente. Cada rama ahora exige esa coincidencia — un evento
-- mal formado queda sin resolver (NULL) en vez de arriesgar una
-- escritura cross-tenant.
--
-- Idempotente igual que 042.
-- =========================================================

update domain_events de
set work_order_id = wo.id
from work_orders wo
where de.work_order_id is null and de.entity_type = 'work_order' and wo.id = de.entity_id and wo.organization_id = de.organization_id;

update domain_events de
set work_order_id = a.work_order_id
from appointments a
where de.work_order_id is null and de.entity_type = 'appointment' and a.id = de.entity_id and a.organization_id = de.organization_id;

update domain_events de
set work_order_id = m.work_order_id
from media_assets m
where de.work_order_id is null and de.entity_type = 'media_asset' and m.id = de.entity_id and m.organization_id = de.organization_id;

update domain_events de
set work_order_id = wn.work_order_id
from work_notes wn
where de.work_order_id is null and de.entity_type = 'work_note' and wn.id = de.entity_id and wn.organization_id = de.organization_id;

update domain_events de
set work_order_id = ms.work_order_id
from measurements ms
where de.work_order_id is null and de.entity_type = 'measurement' and ms.id = de.entity_id and ms.organization_id = de.organization_id;

update domain_events de
set work_order_id = cr.work_order_id
from checklist_responses cr
where de.work_order_id is null and de.entity_type = 'checklist_response' and cr.id = de.entity_id and cr.organization_id = de.organization_id;

update domain_events de
set work_order_id = pu.work_order_id
from progress_updates pu
where de.work_order_id is null and de.entity_type = 'progress_update' and pu.id = de.entity_id and pu.organization_id = de.organization_id;

update domain_events de
set work_order_id = te.work_order_id
from time_entries te
where de.work_order_id is null and de.entity_type = 'time_entry' and te.id = de.entity_id and te.organization_id = de.organization_id;
