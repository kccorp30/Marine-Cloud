-- =========================================================
-- 245_billing_admin_notification_strategy.sql — Phase 14 absolute final closure
-- =========================================================
-- BUG REAL DE REPLAY LIMPIO: la versión original de esta migración
-- hacía el UPDATE de notification_rules ANTES de que 246 extendiera
-- el CHECK constraint que permite 'billing_admin' — en una base
-- limpia, 245 fallaría al intentar guardar un valor que el
-- constraint todavía no permite. Reescrita para ser autocontenida y
-- correcta en un replay limpio: extiende el constraint, crea la
-- función completa (incluida la rama 'billing_admin' — antes
-- separada en 247 por el mismo problema de orden), y SOLO ENTONCES
-- actualiza las reglas. 246 y 247 quedan como no-ops idempotentes
-- (mismo estado final, nunca fallan si se re-corren).
-- =========================================================

alter table notification_rules drop constraint if exists notification_rules_recipient_strategy_check;
alter table notification_rules add constraint notification_rules_recipient_strategy_check
  check (recipient_strategy = any (array['org_staff', 'billing_admin', 'assigned_technician', 'customer', 'kcc_admin', 'requesting_technician']));

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

update notification_rules set recipient_strategy = 'billing_admin'
where event_type in (
  'SUBSCRIPTION_TRIAL_STARTED', 'SUBSCRIPTION_TRIAL_EXTENDED', 'SUBSCRIPTION_ACTIVATED',
  'SUBSCRIPTION_PLAN_CHANGED', 'SUBSCRIPTION_CANCELLED', 'ORGANIZATION_ARCHIVED', 'ORGANIZATION_REACTIVATED'
);
