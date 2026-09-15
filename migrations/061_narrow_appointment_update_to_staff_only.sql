-- =========================================================
-- 061_narrow_appointment_update_to_staff_only.sql — Phase 5 hardening
-- =========================================================
-- BUG REAL: staff_write_appointments_update incluía
-- is_assigned_to_work_order(work_order_id) — un técnico asignado
-- podía hacer UPDATE directo sobre la cita (reprogramar, cancelar,
-- tocar campos administrativos), no solo hacer check-in/check-out.
--
-- Verificado antes de tocar nada: technician_check_in() y
-- technician_check_out() son SECURITY DEFINER y hacen su propio
-- UPDATE interno sobre appointments — bypasean RLS por diseño, así
-- que NO dependen de que la policy incluya al técnico. Quitar esa
-- cláusula no rompe ningún flujo legítimo de técnico — verificado con
-- check-in y check-out reales después del cambio, ambos PASS.
--
-- Administración de citas queda limitada a kcc_admin y staff de la
-- organización.
-- =========================================================

drop policy if exists "staff_write_appointments_update" on appointments;

create policy "staff_write_appointments_update" on appointments for update
using (is_kcc_admin() or is_org_staff(organization_id))
with check (is_kcc_admin() or is_org_staff(organization_id));
