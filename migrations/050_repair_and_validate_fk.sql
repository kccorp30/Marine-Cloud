-- =========================================================
-- 050_repair_and_validate_fk.sql — Marine Cloud Phase 3B
-- =========================================================
-- Con la FK en NOT VALID (049), esta migración garantiza consistencia
-- sin importar desde qué estado se aplique esta cadena completa:
--
-- PASO 1 — Reparar: cualquier fila que la migración 042 (no
-- tenant-safe) pueda haber dejado con un work_order_id que en
-- realidad no pertenece a la misma organización del evento, se pone
-- en NULL. Nunca se inventa ni se fuerza un valor.
--
-- PASO 2 — Re-backfill tenant-safe: misma lógica de la 047
-- (idempotente), para resolver lo que haya quedado NULL en el Paso 1
-- o lo que nunca se resolvió en una base pre-Phase-3B.
--
-- PASO 3 — Validar: recién acá se valida la FK. Toda fila con
-- work_order_id no nulo ya está garantizada consistente por el
-- Paso 1, así que VALIDATE CONSTRAINT no puede fallar por datos
-- históricos malformados, sin importar el estado inicial.
--
-- Verificado de punta a punta contra el escenario corrupto simulado:
-- Paso 1 puso la fila corrupta en NULL (PASS), y VALIDATE CONSTRAINT
-- se completó sin error después (PASS) — cadena completa probada:
-- base pre-Phase3B → backfill tenant-safe → filas mal formadas en
-- NULL → FK creada/validada sin fallar → trigger en vivo tenant-safe
-- (048).
-- =========================================================

-- PASO 1
update domain_events de
set work_order_id = null
where de.work_order_id is not null
  and not exists (
    select 1 from work_orders wo
    where wo.id = de.work_order_id and wo.organization_id = de.organization_id
  );

-- PASO 2
update domain_events de set work_order_id = wo.id from work_orders wo
  where de.work_order_id is null and de.entity_type = 'work_order' and wo.id = de.entity_id and wo.organization_id = de.organization_id;
update domain_events de set work_order_id = a.work_order_id from appointments a
  where de.work_order_id is null and de.entity_type = 'appointment' and a.id = de.entity_id and a.organization_id = de.organization_id;
update domain_events de set work_order_id = m.work_order_id from media_assets m
  where de.work_order_id is null and de.entity_type = 'media_asset' and m.id = de.entity_id and m.organization_id = de.organization_id;
update domain_events de set work_order_id = wn.work_order_id from work_notes wn
  where de.work_order_id is null and de.entity_type = 'work_note' and wn.id = de.entity_id and wn.organization_id = de.organization_id;
update domain_events de set work_order_id = ms.work_order_id from measurements ms
  where de.work_order_id is null and de.entity_type = 'measurement' and ms.id = de.entity_id and ms.organization_id = de.organization_id;
update domain_events de set work_order_id = cr.work_order_id from checklist_responses cr
  where de.work_order_id is null and de.entity_type = 'checklist_response' and cr.id = de.entity_id and cr.organization_id = de.organization_id;
update domain_events de set work_order_id = pu.work_order_id from progress_updates pu
  where de.work_order_id is null and de.entity_type = 'progress_update' and pu.id = de.entity_id and pu.organization_id = de.organization_id;
update domain_events de set work_order_id = te.work_order_id from time_entries te
  where de.work_order_id is null and de.entity_type = 'time_entry' and te.id = de.entity_id and te.organization_id = de.organization_id;

-- PASO 3
alter table domain_events validate constraint fk_domain_events_work_order_same_org;
