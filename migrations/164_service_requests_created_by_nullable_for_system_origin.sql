-- =========================================================
-- 164_service_requests_created_by_nullable_for_system_origin.sql — Phase 11
-- =========================================================
-- BUG REAL encontrado probando convert_website_lead(): created_by
-- referencia profiles(id), pero un lead del sitio web convertido
-- automáticamente vía service_role no tiene ningún actor humano — el
-- customer recién creado tampoco tiene profile_id (sin cuenta).
-- created_by pasa a ser nullable — NULL significa genuinamente "el
-- sistema lo creó automáticamente a partir de un lead".
-- =========================================================

alter table service_requests alter column created_by drop not null;

create or replace function convert_website_lead(p_lead_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lead leads%rowtype;
  v_org_id uuid;
  v_customer_id uuid;
  v_vessel_id uuid;
  v_sr_id uuid;
begin
  if not is_platform_trusted_actor() then
    raise exception 'only trusted platform infrastructure can convert a website lead';
  end if;

  select * into v_lead from leads where id = p_lead_id for update;
  if v_lead.id is null then
    raise exception 'lead not found';
  end if;

  if v_lead.conversion_status = 'converted' then
    return jsonb_build_object(
      'status', 'already_processed',
      'leadId', v_lead.id,
      'organizationId', v_lead.assigned_organization_id,
      'customerId', v_lead.marine_cloud_customer_id,
      'vesselId', v_lead.marine_cloud_vessel_id,
      'serviceRequestId', v_lead.marine_cloud_service_request_id
    );
  end if;

  update leads set attempt_count = attempt_count + 1, last_attempt_at = now(), conversion_status = 'in_progress', updated_at = now()
  where id = p_lead_id;

  begin
    v_org_id := v_lead.assigned_organization_id;
    if v_org_id is null then
      v_org_id := route_website_lead(v_lead.country, v_lead.region, v_lead.service_type);
    end if;

    if v_org_id is null then
      update leads set conversion_status = 'needs_routing', updated_at = now() where id = p_lead_id;
      perform log_domain_event(null, 'WEBSITE_LEAD_ROUTING_REQUIRED', 'lead', p_lead_id,
        jsonb_build_object('country', v_lead.country, 'region', v_lead.region, 'service_type', v_lead.service_type));
      return jsonb_build_object('status', 'needs_routing', 'leadId', p_lead_id);
    end if;

    if v_lead.assigned_organization_id is null then
      update leads set assigned_organization_id = v_org_id, updated_at = now() where id = p_lead_id;
      perform log_domain_event(v_org_id, 'WEBSITE_LEAD_ROUTED', 'lead', p_lead_id, jsonb_build_object('manual', false));
    end if;

    v_customer_id := coalesce(v_lead.marine_cloud_customer_id,
      find_or_create_customer_for_lead(v_org_id, v_lead.customer_name, v_lead.phone, v_lead.email));

    v_vessel_id := coalesce(v_lead.marine_cloud_vessel_id,
      find_or_create_vessel_for_lead(v_org_id, v_customer_id, v_lead.hin, v_lead.vessel_make, v_lead.vessel_model, v_lead.vessel_year, v_lead.vessel_name));

    if v_lead.marine_cloud_service_request_id is not null then
      v_sr_id := v_lead.marine_cloud_service_request_id;
    else
      insert into service_requests (organization_id, customer_id, vessel_id, title, description, client_generated_id, source, website_lead_id, created_by, status)
      values (
        v_org_id, v_customer_id, v_vessel_id,
        coalesce(v_lead.service_type, 'Service Request'), v_lead.description,
        v_lead.idempotency_key, 'website', p_lead_id, auth.uid(), 'submitted'
      )
      returning id into v_sr_id;
    end if;

    update leads set
      conversion_status = 'converted',
      status = case when status = 'new' then 'qualified' else status end,
      marine_cloud_customer_id = v_customer_id,
      marine_cloud_vessel_id = v_vessel_id,
      marine_cloud_service_request_id = v_sr_id,
      converted_at = now(),
      converted_by = auth.uid(),
      conversion_error = null,
      updated_at = now()
    where id = p_lead_id;

    perform log_domain_event(v_org_id, 'WEBSITE_LEAD_CONVERTED', 'lead', p_lead_id,
      jsonb_build_object('customer_id', v_customer_id, 'vessel_id', v_vessel_id, 'service_request_id', v_sr_id));

    return jsonb_build_object(
      'status', 'created',
      'leadId', p_lead_id,
      'organizationId', v_org_id,
      'customerId', v_customer_id,
      'vesselId', v_vessel_id,
      'serviceRequestId', v_sr_id
    );
  exception when others then
    update leads set conversion_status = 'failed', conversion_error = sqlerrm, updated_at = now() where id = p_lead_id;
    perform log_domain_event(v_org_id, 'WEBSITE_LEAD_CONVERSION_FAILED', 'lead', p_lead_id, jsonb_build_object('error', sqlerrm));
    raise;
  end;
end;
$$;
