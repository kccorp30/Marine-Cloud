-- =========================================================
-- 147_enforce_org_status_in_remaining_authorization_helpers.sql — Phase 10 final fix
-- =========================================================
-- BUG REAL: is_assigned_to_work_order()/is_customer_of_work_order()/
-- is_own_customer_record() nunca consideraban organizations.status —
-- un técnico asignado o un customer podían seguir operando sobre una
-- organización suspendida.
--
-- Semántica de suspensión: durante suspensión, TODOS pierden acceso
-- operativo excepto kcc_admin — sin excepción para técnico asignado
-- ni customer.
-- Verificado con matriz completa de 6 roles (owner/admin/manager/
-- technician/customer/kcc_admin) antes y después de suspender.
-- =========================================================

create or replace function is_assigned_to_work_order(p_work_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1 from assignments a
    join work_orders wo on wo.id = a.work_order_id
    join organizations o on o.id = wo.organization_id
    where a.work_order_id = p_work_order_id
      and a.technician_profile_id = auth.uid()
      and a.status = 'active'
      and o.status = 'active'
  );
$function$;

create or replace function is_customer_of_work_order(p_work_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1 from work_orders wo
    join customers c on c.id = wo.customer_id
    join organizations o on o.id = wo.organization_id
    where wo.id = p_work_order_id and c.profile_id = auth.uid() and o.status = 'active'
  );
$function$;

create or replace function is_own_customer_record(p_customer_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1 from customers c
    join organizations o on o.id = c.organization_id
    where c.id = p_customer_id and c.profile_id = auth.uid() and o.status = 'active'
  );
$function$;
