-- =========================================================
-- 241_expand_module_enforcement.sql — Phase 14 true final closure
-- =========================================================
-- Conecta organization_has_module_access() a estimates,
-- service_requests, y warranty (activación). customers/vessels
-- quedan FUERA — datos base del producto, nunca toggleable por plan.
-- Verificado con datos reales: plan sin 'estimates' bloquea
-- create_draft_estimate().
-- =========================================================

create or replace function create_draft_estimate(p_organization_id uuid, p_customer_id uuid, p_vessel_id uuid, p_work_order_id uuid DEFAULT NULL::uuid, p_service_request_id uuid DEFAULT NULL::uuid, p_title text DEFAULT NULL::text, p_customer_message text DEFAULT NULL::text, p_valid_until date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_estimate_id uuid;
  v_version_id uuid;
  v_currency text;
begin
  if not (is_kcc_admin() or is_org_staff(p_organization_id)) then
    raise exception 'not authorized to create estimates';
  end if;
  if not organization_has_active_access(p_organization_id) then
    raise exception 'this organization does not have active commercial access to create new estimates';
  end if;
  if not organization_has_module_access(p_organization_id, 'estimates') then
    raise exception 'this organization''s plan does not include the estimates module';
  end if;

  if not exists (select 1 from customers where id = p_customer_id and organization_id = p_organization_id) then
    raise exception 'customer does not belong to this organization';
  end if;
  if not exists (select 1 from vessels where id = p_vessel_id and organization_id = p_organization_id and current_customer_id = p_customer_id) then
    raise exception 'vessel does not belong to this customer/organization';
  end if;

  if p_work_order_id is not null then
    if not exists (
      select 1 from work_orders
      where id = p_work_order_id and organization_id = p_organization_id
        and customer_id = p_customer_id and vessel_id = p_vessel_id
    ) then
      raise exception 'work order does not match this organization/customer/vessel';
    end if;
  end if;

  if p_service_request_id is not null then
    if not exists (
      select 1 from service_requests
      where id = p_service_request_id and organization_id = p_organization_id
        and customer_id = p_customer_id and vessel_id = p_vessel_id
    ) then
      raise exception 'service request does not match this organization/customer/vessel';
    end if;
  end if;

  select currency into v_currency from organization_settings where organization_id = p_organization_id;
  v_currency := coalesce(v_currency, 'USD');

  insert into estimates (organization_id, customer_id, vessel_id, work_order_id, service_request_id, estimate_number, type, status, currency, created_by)
  values (p_organization_id, p_customer_id, p_vessel_id, p_work_order_id, p_service_request_id,
    generate_estimate_number(p_organization_id, 'estimate'), 'estimate', 'draft', v_currency, auth.uid())
  returning id into v_estimate_id;

  insert into estimate_versions (organization_id, estimate_id, version_number, status, title, customer_message, currency, valid_until, created_by)
  values (p_organization_id, v_estimate_id, 1, 'draft', p_title, p_customer_message, v_currency, p_valid_until, auth.uid())
  returning id into v_version_id;

  update estimates set current_version_id = v_version_id where id = v_estimate_id;

  perform log_domain_event(p_organization_id, 'ESTIMATE_CREATED', 'estimate', v_estimate_id,
    jsonb_build_object('estimate_number', (select estimate_number from estimates where id = v_estimate_id)));

  return v_estimate_id;
end;
$function$;

drop policy "customer_insert_service_requests" on service_requests;
create policy "customer_insert_service_requests" on service_requests for insert
with check (
  is_own_customer_record(customer_id)
  and exists (select 1 from vessels v where v.id = service_requests.vessel_id and v.current_customer_id = service_requests.customer_id and v.organization_id = service_requests.organization_id)
  and status = 'submitted'
  and organization_has_active_access(organization_id)
  and organization_has_module_access(organization_id, 'service_requests')
);

create or replace function activate_warranty(
  p_work_order_id uuid, p_duration_days int default null, p_coverage_type text default 'workmanship', p_coverage_notes text default null
)
returns warranties
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders%rowtype;
  v_service service_catalog%rowtype;
  v_effective_duration int;
  v_effective_notes text;
  v_warranty warranties%rowtype;
  v_has_passed_qc boolean;
begin
  select * into v_wo from work_orders where id = p_work_order_id for update;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;
  if not exists (select 1 from organizations where id = v_wo.organization_id and status = 'active') then
    raise exception 'organization is not active';
  end if;
  if not (is_org_staff(v_wo.organization_id) or is_kcc_admin()) then
    raise exception 'not authorized to activate warranty for this organization';
  end if;
  if not organization_has_module_access(v_wo.organization_id, 'warranty') then
    raise exception 'this organization''s plan does not include the warranty module';
  end if;
  if v_wo.current_status not in ('completed', 'warranty') then
    raise exception 'work order must be completed before warranty can be activated (current: %)', v_wo.current_status;
  end if;

  select * into v_warranty from warranties where work_order_id = p_work_order_id;
  if v_warranty.id is not null then
    return v_warranty;
  end if;

  if v_wo.qc_required then
    select exists (select 1 from qc_submissions where work_order_id = p_work_order_id and status = 'passed') into v_has_passed_qc;
    if not v_has_passed_qc then
      raise exception 'this work order requires a passed QC submission before warranty can be activated';
    end if;
  end if;

  if v_wo.service_id is not null then
    select * into v_service from service_catalog where id = v_wo.service_id and warranty_enabled = true;
  end if;

  v_effective_duration := coalesce(p_duration_days, v_service.warranty_duration_days);
  v_effective_notes := coalesce(p_coverage_notes, v_service.warranty_coverage_notes);

  if v_effective_duration is null then
    raise exception 'no warranty duration available — this service has no warranty configured and none was explicitly provided';
  end if;
  if v_effective_duration <= 0 then
    raise exception 'warranty duration must be positive';
  end if;

  insert into warranties (
    organization_id, work_order_id, customer_id, vessel_id, status, coverage_type, coverage_notes,
    starts_at, ends_at, created_by, activated_at
  )
  values (
    v_wo.organization_id, p_work_order_id, v_wo.customer_id, v_wo.vessel_id, 'active', p_coverage_type, v_effective_notes,
    current_date, current_date + (v_effective_duration || ' days')::interval, auth.uid(), now()
  )
  returning * into v_warranty;

  perform log_domain_event(v_wo.organization_id, 'WARRANTY_ACTIVATED', 'warranty', v_warranty.id,
    jsonb_build_object('warranty_id', v_warranty.id, 'ends_at', v_warranty.ends_at));
  perform log_audit_event(v_wo.organization_id, 'warranty', v_warranty.id, 'warranty_activated',
    null, jsonb_build_object('ends_at', v_warranty.ends_at, 'coverage_type', p_coverage_type));

  return v_warranty;
end;
$$;
