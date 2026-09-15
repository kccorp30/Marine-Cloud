-- =========================================================
-- 110_validate_conversation_context.sql — Phase 8 hardening
-- =========================================================
-- BUG REAL: get_or_create_conversation() validaba el customer contra
-- la organización, pero nunca que vessel/work_order/service_request
-- realmente pertenecieran a ESE customer. Verificado: work order de
-- otro customer rechazado.
-- =========================================================

create or replace function get_or_create_conversation(
  p_organization_id uuid,
  p_customer_id uuid,
  p_vessel_id uuid default null,
  p_work_order_id uuid default null,
  p_service_request_id uuid default null,
  p_subject text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conversation_id uuid;
begin
  if not (is_kcc_admin() or is_org_staff(p_organization_id)) then
    raise exception 'not authorized';
  end if;
  if not exists (select 1 from customers where id = p_customer_id and organization_id = p_organization_id) then
    raise exception 'customer does not belong to this organization';
  end if;

  if p_vessel_id is not null then
    if not exists (select 1 from vessels where id = p_vessel_id and organization_id = p_organization_id and current_customer_id = p_customer_id) then
      raise exception 'vessel does not belong to this customer/organization';
    end if;
  end if;

  if p_work_order_id is not null then
    if not exists (
      select 1 from work_orders
      where id = p_work_order_id and organization_id = p_organization_id and customer_id = p_customer_id
        and (p_vessel_id is null or vessel_id = p_vessel_id)
    ) then
      raise exception 'work order does not match this organization/customer/vessel';
    end if;
  end if;

  if p_service_request_id is not null then
    if not exists (
      select 1 from service_requests
      where id = p_service_request_id and organization_id = p_organization_id and customer_id = p_customer_id
        and (p_vessel_id is null or vessel_id = p_vessel_id)
    ) then
      raise exception 'service request does not match this organization/customer/vessel';
    end if;
  end if;

  select id into v_conversation_id from conversations
  where organization_id = p_organization_id and customer_id = p_customer_id
    and status = 'open'
    and coalesce(work_order_id::text, '') = coalesce(p_work_order_id::text, '')
  limit 1;

  if v_conversation_id is not null then
    return v_conversation_id;
  end if;

  insert into conversations (organization_id, customer_id, vessel_id, work_order_id, service_request_id, subject, created_by)
  values (p_organization_id, p_customer_id, p_vessel_id, p_work_order_id, p_service_request_id, p_subject, auth.uid())
  returning id into v_conversation_id;

  return v_conversation_id;
end;
$$;
