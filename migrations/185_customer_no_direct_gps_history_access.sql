-- =========================================================
-- 185_customer_no_direct_gps_history_access.sql — Phase 12 final fix
-- =========================================================
-- BUG REAL: las policies de SELECT permitían is_customer_of_work_order
-- directo sobre technician_tracking_sessions/technician_locations —
-- violaba el modelo de privacidad documentado. El customer ahora solo
-- lee vía get_work_order_tracking_status(). Staff/técnico/kcc_admin
-- retienen acceso directo (operacionalmente justificado).
-- Verificado con datos reales: customer no puede SELECT crudo de
-- ninguna de las dos tablas, sigue pudiendo llamar la RPC.
-- =========================================================

drop policy if exists "technician_reads_own_tracking_sessions" on technician_tracking_sessions;
create policy "technician_reads_own_tracking_sessions" on technician_tracking_sessions for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (technician_profile_id = auth.uid() and is_org_active(organization_id))
);

drop policy if exists "technician_reads_own_locations" on technician_locations;
create policy "technician_reads_own_locations" on technician_locations for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (technician_profile_id = auth.uid() and is_org_active(organization_id))
);
