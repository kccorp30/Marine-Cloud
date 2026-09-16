-- =========================================================
-- 041_checkins_customer_visibility.sql — Marine Cloud Phase 3
-- =========================================================
-- Inconsistencia encontrada construyendo el timeline: el evento
-- TECHNICIAN_CHECKED_IN ya es customer_visible (migración 040), pero
-- la tabla check_ins en sí no dejaba leer al customer — el estado
-- operativo "on site" nunca se le mostraba aunque el evento que lo
-- anuncia sí. Verificado con test real: customer ve su check-in activo.
-- =========================================================

drop policy if exists "read_check_ins" on check_ins;

create policy "read_check_ins" on check_ins for select
  using (
    is_kcc_admin()
    or is_org_staff(organization_id)
    or technician_profile_id = auth.uid()
    or is_customer_of_work_order(work_order_id)
  );
