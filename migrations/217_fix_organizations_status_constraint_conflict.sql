-- =========================================================
-- 217_fix_organizations_status_constraint_conflict.sql — Marine Cloud Phase 14
-- =========================================================
-- BUG REAL PREEXISTENTE: dos CHECK constraints simultáneos en
-- organizations.status con intersección real de solo active/
-- suspended — 'inactive' y 'archived' nunca fueron insertables.
-- Consolidado en un solo constraint con los 4 valores reales.
-- =========================================================

alter table organizations drop constraint chk_organizations_status;
alter table organizations drop constraint organizations_status_check;
alter table organizations add constraint organizations_status_check
  check (status = any (array['active', 'inactive', 'suspended', 'archived']));
