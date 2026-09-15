-- =========================================================
-- 049_fk_not_valid_for_safe_reorder.sql — Marine Cloud Phase 3B
-- =========================================================
-- PROBLEMA REAL DE ORDEN: en una base que sube desde pre-Phase-3B con
-- eventos históricos mal formados, la migración 042 (backfill
-- original, sin verificación de tenant) corre ANTES que la 043 (FK
-- compuesta) — si 042 llegara a dejar work_order_id con una
-- organización inconsistente, 043 fallaría al crear la FK (valida
-- TODAS las filas existentes por defecto), y la 047 tenant-safe nunca
-- llega a tiempo para prevenirlo.
--
-- 042 y 043 se tratan como inmutables (ya desplegadas) — no se
-- reescriben. Patrón estándar de Postgres: la FK ya existente pasa a
-- NOT VALID (nunca falla, sin importar el estado de los datos — no
-- revalida nada al hacerlo), dejando la reparación real y la
-- validación final para la migración 050.
--
-- Verificado con un escenario simulado real: se recreó una fila
-- exactamente como 042 podía haberla dejado corrupta (organization_id
-- de Org B, work_order_id apuntando a un work order real de Org A), y
-- esta migración se aplicó sin error contra esos datos.
-- =========================================================

alter table domain_events drop constraint if exists fk_domain_events_work_order_same_org;

alter table domain_events
  add constraint fk_domain_events_work_order_same_org
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id)
  not valid;
