-- =========================================================
-- 069_estimate_service_request_and_work_order_bridge.sql — Phase 6
-- =========================================================
-- Crear estimate desde un service request — customer_id/vessel_id/
-- organization_id se derivan del propio service_request server-side,
-- nunca de un parámetro que mande el cliente.
--
-- convert_estimate_to_work_order: idempotente/concurrency-safe —
-- verificado con datos reales llamándola dos veces: exactamente un
-- work order creado, la segunda llamada reusa el mismo id (row lock
-- sobre la estimate).
-- =========================================================

create or replace function create_estimate_from_service_request(
  p_service_request_id uuid,
  p_title text default null,
  p_customer_message text default null,
  p_valid_until date default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sr service_requests%rowtype;
begin
  select * into v_sr from service_requests where id = p_service_request_id;
  if v_sr.id is null then
    raise exception 'service request not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_sr.organization_id)) then
    raise exception 'not authorized';
  end if;

  return create_draft_estimate(
    v_sr.organization_id, v_sr.customer_id, v_sr.vessel_id,
    null, p_service_request_id,
    coalesce(p_title, v_sr.title), coalesce(p_customer_message, v_sr.description), p_valid_until
  );
end;
$$;

revoke execute on function create_estimate_from_service_request(uuid, text, text, date) from public, anon;
grant execute on function create_estimate_from_service_request(uuid, text, text, date) to authenticated;

create or replace function convert_estimate_to_work_order(p_estimate_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estimate estimates%rowtype;
  v_work_order_id uuid;
begin
  select * into v_estimate from estimates where id = p_estimate_id for update;
  if v_estimate.id is null then
    raise exception 'estimate not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_estimate.organization_id)) then
    raise exception 'not authorized';
  end if;
  if v_estimate.status != 'approved' then
    raise exception 'estimate must be approved before creating a work order (status: %)', v_estimate.status;
  end if;

  if v_estimate.work_order_id is not null then
    return v_estimate.work_order_id;
  end if;

  insert into work_orders (organization_id, customer_id, vessel_id, title, created_by)
  values (v_estimate.organization_id, v_estimate.customer_id, v_estimate.vessel_id,
    coalesce((select title from estimate_versions where id = v_estimate.current_version_id), 'Approved Work'), auth.uid())
  returning id into v_work_order_id;

  update estimates set work_order_id = v_work_order_id, updated_at = now() where id = p_estimate_id;

  return v_work_order_id;
end;
$$;

revoke execute on function convert_estimate_to_work_order(uuid) from public, anon;
grant execute on function convert_estimate_to_work_order(uuid) to authenticated;
