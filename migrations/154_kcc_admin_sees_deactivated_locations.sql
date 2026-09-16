-- =========================================================
-- 154_kcc_admin_sees_deactivated_locations.sql — Phase 10 final closure
-- =========================================================
-- BUG REAL encontrado revisando 153: la policy nueva ocultaba
-- locations desactivadas incluso a kcc_admin — pierde valor de
-- auditoría/historial. kcc_admin sí las ve, org staff/miembros
-- normales solo ven las activas.
-- Verificado con datos reales: staff ve solo 1 (activa), kcc_admin
-- ve 2 (para auditoría).
-- =========================================================

drop policy if exists "read_locations" on organization_locations;
create policy "read_locations" on organization_locations for select
using (
  is_kcc_admin()
  or ((is_org_staff(organization_id) or is_org_member(organization_id)) and deleted_at is null)
);
