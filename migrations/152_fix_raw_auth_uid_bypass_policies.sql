-- =========================================================
-- 152_fix_raw_auth_uid_bypass_policies.sql — Phase 10 final closure
-- =========================================================
-- BUG REAL: 9 policies de SELECT/UPDATE (assignments, check_ins,
-- customer_relationships, customers, measurements, technician_
-- relationships x2, time_entries x2, work_notes) tenían una rama OR
-- cruda "X = auth.uid()" que nunca pasaba por is_org_staff()/
-- is_assigned_to_work_order() (ya corregidos en 139/147) — un
-- técnico o customer podía seguir leyendo/actualizando SU PROPIA
-- fila en una organización suspendida. Las policies de INSERT
-- (auditadas también) ya estaban bien — combinan auth.uid() con
-- is_assigned_to_work_order() vía AND. Las policies de storage
-- vessel-media también auditadas: ya usan exclusivamente los
-- helpers corregidos, sin cambios necesarios. organization_memberships
-- y profiles: excepción intencional documentada — un usuario siempre
-- ve su propia membresía/perfil (no es acceso operativo, es
-- identidad básica necesaria para que la UI funcione).
--
-- is_org_active() — helper mínimo nuevo para los casos puntuales sin
-- helper existente.
--
-- Verificado con datos reales: técnico pierde acceso a su propia
-- time_entry al suspender, customer pierde acceso a su propio
-- registro, kcc_admin retiene ambos.
-- =========================================================

create or replace function is_org_active(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (select 1 from organizations where id = p_organization_id and status = 'active');
$function$;

revoke execute on function is_org_active(uuid) from public, anon;
grant execute on function is_org_active(uuid) to authenticated;

drop policy if exists "read_assignments" on assignments;
create policy "read_assignments" on assignments for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (technician_profile_id = auth.uid() and is_org_active(organization_id))
  or is_assigned_to_work_order(work_order_id)
  or is_customer_of_work_order(work_order_id)
);

drop policy if exists "read_check_ins" on check_ins;
create policy "read_check_ins" on check_ins for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (technician_profile_id = auth.uid() and is_org_active(organization_id))
  or is_customer_of_work_order(work_order_id)
);

drop policy if exists "read_customer_relationships" on customer_relationships;
create policy "read_customer_relationships" on customer_relationships for select
using (
  (profile_id = auth.uid() and is_org_active(organization_id))
  or is_kcc_admin()
  or is_org_member(organization_id)
);

drop policy if exists "read_customers" on customers;
create policy "read_customers" on customers for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (profile_id = auth.uid() and is_org_active(organization_id))
  or exists (select 1 from work_orders wo where wo.customer_id = customers.id and is_assigned_to_work_order(wo.id))
);

drop policy if exists "staff_update_measurements" on measurements;
create policy "staff_update_measurements" on measurements for update
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (technician_profile_id = auth.uid() and is_assigned_to_work_order(work_order_id))
);

drop policy if exists "read_technician_relationships" on technician_relationships;
create policy "read_technician_relationships" on technician_relationships for select
using (
  (profile_id = auth.uid() and is_org_active(organization_id))
  or is_kcc_admin()
  or is_org_member(organization_id)
);

drop policy if exists "staff_manage_technicians_update" on technician_relationships;
create policy "staff_manage_technicians_update" on technician_relationships for update
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (profile_id = auth.uid() and is_org_active(organization_id))
);

drop policy if exists "read_time_entries" on time_entries;
create policy "read_time_entries" on time_entries for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (technician_profile_id = auth.uid() and is_org_active(organization_id))
);

drop policy if exists "technician_update_own_time_entries" on time_entries;
create policy "technician_update_own_time_entries" on time_entries for update
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (technician_profile_id = auth.uid() and is_assigned_to_work_order(work_order_id))
);

drop policy if exists "staff_update_work_notes" on work_notes;
create policy "staff_update_work_notes" on work_notes for update
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or (technician_profile_id = auth.uid() and is_assigned_to_work_order(work_order_id))
);
