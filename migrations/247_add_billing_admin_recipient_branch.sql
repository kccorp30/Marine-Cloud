-- =========================================================
-- 247_add_billing_admin_recipient_branch.sql — Phase 14 absolute final closure
-- =========================================================
-- NO-OP idempotente: la función completa (con la rama 'billing_admin')
-- ya se crea en 245 reescrita. Este archivo queda como CREATE OR
-- REPLACE del mismo cuerpo final — re-aplicarlo es un no-op real,
-- nunca falla ni cambia el comportamiento.
-- =========================================================

create or replace function resolve_notification_recipients(p_recipient_strategy text, p_organization_id uuid, p_work_order_id uuid, p_entity_type text, p_entity_id uuid)
 RETURNS SETOF uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_recipient_strategy = 'org_staff' then
    return query
      select profile_id from organization_memberships
      where organization_id = p_organization_id and status = 'active'
        and role in ('company_owner', 'company_admin', 'manager');

  elsif p_recipient_strategy = 'billing_admin' then
    return query
      select profile_id from organization_memberships
      where organization_id = p_organization_id and status = 'active'
        and role in ('company_owner', 'company_admin');

  elsif p_recipient_strategy = 'assigned_technician' then
    return query
      select technician_profile_id from assignments
      where work_order_id = p_work_order_id and status = 'active';

  elsif p_recipient_strategy = 'customer' then
    return query
      select c.profile_id from work_orders wo
      join customers c on c.id = wo.customer_id
      where wo.id = p_work_order_id and c.profile_id is not null;

  elsif p_recipient_strategy = 'kcc_admin' then
    return query
      select distinct profile_id from organization_memberships
      where role = 'kcc_admin' and status = 'active';

  elsif p_recipient_strategy = 'requesting_technician' then
    if p_entity_type = 'kcc_assistance_request' then
      return query
        select requesting_technician_id from kcc_assistance_requests where id = p_entity_id;
    end if;
    return;
  end if;

  return;
end;
$function$;
