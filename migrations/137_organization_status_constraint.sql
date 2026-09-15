-- =========================================================
-- 137_organization_status_constraint.sql — Marine Cloud Phase 10
-- =========================================================
-- Paso 0 (reportado): organizations.status ya existe (text, sin
-- constraint) — se le agrega el CHECK explícito. organization_settings,
-- organization_locations, work_orders.kcc_generated, y la policy
-- kcc_admin_creates_orgs (INSERT, with_check is_kcc_admin()) ya
-- existían — se reusan, ninguno se duplica.
-- =========================================================

alter table organizations add constraint chk_organizations_status check (status in ('active', 'inactive', 'suspended'));
