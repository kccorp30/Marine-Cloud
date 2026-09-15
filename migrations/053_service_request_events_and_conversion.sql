-- =========================================================
-- 053_service_request_events_and_conversion.sql — Marine Cloud Phase 4B
-- =========================================================

create or replace function trg_emit_service_request_submitted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform log_domain_event(new.organization_id, 'CUSTOMER_SERVICE_REQUEST_SUBMITTED', 'service_request', new.id,
    jsonb_build_object('vessel_id', new.vessel_id, 'urgency', new.urgency));
  return new;
end;
$$;

create trigger trg_service_request_submitted
  after insert on service_requests
  for each row execute function trg_emit_service_request_submitted();

create or replace function trg_emit_service_request_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = old.status then
    return new;
  end if;
  if new.status = 'cancelled' then
    perform log_domain_event(new.organization_id, 'CUSTOMER_SERVICE_REQUEST_CANCELLED', 'service_request', new.id, jsonb_build_object('from_status', old.status));
  elsif new.status = 'accepted' then
    perform log_domain_event(new.organization_id, 'SERVICE_REQUEST_ACCEPTED', 'service_request', new.id, jsonb_build_object('from_status', old.status));
  elsif new.status = 'declined' then
    perform log_domain_event(new.organization_id, 'SERVICE_REQUEST_DECLINED', 'service_request', new.id, jsonb_build_object('from_status', old.status, 'reason', new.decline_reason));
  end if;
  return new;
end;
$$;

create trigger trg_service_request_status_change
  after update on service_requests
  for each row execute function trg_emit_service_request_status_change();

revoke execute on function trg_emit_service_request_submitted() from public, anon, authenticated;
revoke execute on function trg_emit_service_request_status_change() from public, anon, authenticated;

create or replace function convert_service_request_to_work_order(
  p_request_id uuid,
  p_title text default null,
  p_description text default null,
  p_priority text default 'normal'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request service_requests%rowtype;
  v_work_order_id uuid;
begin
  select * into v_request from service_requests where id = p_request_id;
  if v_request.id is null then
    raise exception 'service request not found';
  end if;

  if not (is_kcc_admin() or is_org_staff(v_request.organization_id)) then
    raise exception 'not authorized';
  end if;

  if v_request.status not in ('submitted', 'under_review', 'accepted') then
    raise exception 'service request cannot be converted from status %', v_request.status;
  end if;

  insert into work_orders (organization_id, customer_id, vessel_id, title, description, priority, created_by)
  values (
    v_request.organization_id,
    v_request.customer_id,
    v_request.vessel_id,
    coalesce(p_title, v_request.title),
    coalesce(p_description, v_request.description),
    coalesce(p_priority, case v_request.urgency when 'urgent' then 'urgent' when 'high' then 'high' when 'low' then 'low' else 'normal' end),
    auth.uid()
  )
  returning id into v_work_order_id;

  update service_requests
  set status = 'converted', converted_work_order_id = v_work_order_id, reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_request_id;

  perform log_domain_event(v_request.organization_id, 'SERVICE_REQUEST_CONVERTED', 'service_request', p_request_id,
    jsonb_build_object('work_order_id', v_work_order_id));

  return v_work_order_id;
end;
$$;

revoke execute on function convert_service_request_to_work_order(uuid, text, text, text) from public, anon;
grant execute on function convert_service_request_to_work_order(uuid, text, text, text) to authenticated;
