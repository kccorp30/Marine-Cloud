-- =========================================================
-- 051_customer_read_own_vessel_systems.sql — Marine Cloud Phase 4
-- =========================================================
-- Gap real encontrado construyendo la página de detalle de vessel:
-- read_vessel_systems nunca incluía al customer dueño del vessel —
-- solo kcc_admin, staff, y el técnico asignado. Datos de specs
-- (fabricante/modelo de sus propios sistemas), no información
-- sensible — coherente con "vista de solo lectura de sus propios
-- vessels" de Phase 4. Mismo patrón que ya usa vessels.read_vessels
-- (is_own_customer_record vía el vessel relacionado).
--
-- Verificado: el customer dueño ve los sistemas de su vessel (PASS),
-- otro customer no (PASS).
-- =========================================================

drop policy if exists "read_vessel_systems" on vessel_systems;

create policy "read_vessel_systems" on vessel_systems for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or exists (
    select 1 from vessels v
    where v.id = vessel_systems.vessel_id and is_own_customer_record(v.current_customer_id)
  )
  or exists (
    select 1 from work_orders wo
    where wo.vessel_id = vessel_systems.vessel_id and is_assigned_to_work_order(wo.id)
  )
);
