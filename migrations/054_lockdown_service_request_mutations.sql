-- =========================================================
-- 054_lockdown_service_request_mutations.sql — Phase 4B hardening
-- =========================================================
-- BUG REAL: ni customer_cancel_own_service_request ni
-- staff_review_service_requests restringían QUÉ columnas cambian —
-- RLS solo valida el estado final de la fila, no qué campos se
-- tocaron en el mismo UPDATE. Un customer podía, en el mismo UPDATE
-- que cancela su pedido, colar un cambio a vessel_id/customer_id/etc.
-- Staff tenía el mismo problema, más amplio.
--
-- FIX: se revoca UPDATE directo por completo. Las tres únicas puertas
-- de mutación son funciones SECURITY DEFINER, cada una haciendo un
-- UPDATE interno que toca EXACTAMENTE las columnas de esa transición
-- — column-lock real, no solo row-level. Verificado: un UPDATE crudo
-- ahora falla con "permission denied", no solo con RLS.
-- =========================================================

drop policy if exists "customer_cancel_own_service_request" on service_requests;
drop policy if exists "staff_review_service_requests" on service_requests;
revoke update on service_requests from authenticated;

create or replace function cancel_service_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request service_requests%rowtype;
begin
  select * into v_request from service_requests where id = p_request_id for update;
  if v_request.id is null then
    raise exception 'service request not found';
  end if;
  if not is_own_customer_record(v_request.customer_id) then
    raise exception 'not authorized';
  end if;
  if v_request.status not in ('submitted', 'under_review') then
    raise exception 'service request cannot be cancelled from status %', v_request.status;
  end if;

  update service_requests set status = 'cancelled', updated_at = now() where id = p_request_id;
end;
$$;

revoke execute on function cancel_service_request(uuid) from public, anon;
grant execute on function cancel_service_request(uuid) to authenticated;

create or replace function accept_service_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request service_requests%rowtype;
begin
  select * into v_request from service_requests where id = p_request_id for update;
  if v_request.id is null then
    raise exception 'service request not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_request.organization_id)) then
    raise exception 'not authorized';
  end if;
  if v_request.status not in ('submitted', 'under_review') then
    raise exception 'service request cannot be accepted from status %', v_request.status;
  end if;

  update service_requests set status = 'accepted', reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now() where id = p_request_id;
end;
$$;

revoke execute on function accept_service_request(uuid) from public, anon;
grant execute on function accept_service_request(uuid) to authenticated;

create or replace function decline_service_request(p_request_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request service_requests%rowtype;
begin
  select * into v_request from service_requests where id = p_request_id for update;
  if v_request.id is null then
    raise exception 'service request not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_request.organization_id)) then
    raise exception 'not authorized';
  end if;
  if v_request.status not in ('submitted', 'under_review', 'accepted') then
    raise exception 'service request cannot be declined from status %', v_request.status;
  end if;

  update service_requests set status = 'declined', decline_reason = p_reason, reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now() where id = p_request_id;
end;
$$;

revoke execute on function decline_service_request(uuid, text) from public, anon;
grant execute on function decline_service_request(uuid, text) to authenticated;

-- Conversión — se le agrega SELECT ... FOR UPDATE para que dos
-- conversiones simultáneas del mismo pedido no puedan crear dos work
-- orders (antes ya era segura contra doble conversión SECUENCIAL por
-- el chequeo de status, pero no contra una carrera real).
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
  select * into v_request from service_requests where id = p_request_id for update;
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
  set status = 'converted', converted_work_order_id = v_work_order_id, reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
  where id = p_request_id;

  perform log_domain_event(v_request.organization_id, 'SERVICE_REQUEST_CONVERTED', 'service_request', p_request_id,
    jsonb_build_object('work_order_id', v_work_order_id));

  return v_work_order_id;
end;
$$;

revoke execute on function convert_service_request_to_work_order(uuid, text, text, text) from public, anon;
grant execute on function convert_service_request_to_work_order(uuid, text, text, text) to authenticated;
