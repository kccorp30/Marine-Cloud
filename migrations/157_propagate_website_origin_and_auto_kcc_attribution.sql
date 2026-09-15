-- =========================================================
-- 157_propagate_website_origin_and_auto_kcc_attribution.sql — Phase 11
-- =========================================================
-- Extiende convert_service_request_to_work_order() (Phase 4B, ya
-- existente — nunca se bypassea, se reusa tal cual salvo esta
-- propagación) para copiar website_lead_id/source al work order
-- resultante. Trigger AFTER INSERT separado marca kcc_generated=true
-- automáticamente SOLO cuando el work order realmente vino de un
-- lead del sitio oficial, usando el mismo mecanismo de confianza de
-- Phase 10. Si no hay acuerdo vigente: NO bloquea la creación del
-- work order — persiste un estado no resuelto explícito en
-- leads.integration_error.
-- =========================================================

create or replace function convert_service_request_to_work_order(p_request_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_priority text DEFAULT 'normal'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  insert into work_orders (organization_id, customer_id, vessel_id, title, description, priority, created_by, source, website_lead_id)
  values (
    v_request.organization_id,
    v_request.customer_id,
    v_request.vessel_id,
    coalesce(p_title, v_request.title),
    coalesce(p_description, v_request.description),
    coalesce(p_priority, case v_request.urgency when 'urgent' then 'urgent' when 'high' then 'high' when 'low' then 'low' else 'normal' end),
    auth.uid(),
    v_request.source,
    v_request.website_lead_id
  )
  returning id into v_work_order_id;

  update service_requests
  set status = 'converted', converted_work_order_id = v_work_order_id, reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
  where id = p_request_id;

  perform log_domain_event(v_request.organization_id, 'SERVICE_REQUEST_CONVERTED', 'service_request', p_request_id,
    jsonb_build_object('work_order_id', v_work_order_id));

  return v_work_order_id;
end;
$function$;

create or replace function auto_attribute_website_work_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.website_lead_id is not null and NEW.source = 'website' then
    begin
      perform set_config('app.kcc_generated_via_trusted_rpc', 'true', true);
      update work_orders set kcc_generated = true where id = NEW.id;
      perform attribute_kcc_work(NEW.id);
      perform set_config('app.kcc_generated_via_trusted_rpc', 'false', true);
    exception when others then
      perform set_config('app.kcc_generated_via_trusted_rpc', 'false', true);
      update leads set integration_error = 'KCC attribution pending: ' || sqlerrm, updated_at = now()
      where id = NEW.website_lead_id;
    end;
  end if;
  return NEW;
end;
$$;

create trigger trg_auto_attribute_website_work_order
  after insert on work_orders
  for each row execute function auto_attribute_website_work_order();

revoke execute on function auto_attribute_website_work_order() from public, anon, authenticated;
