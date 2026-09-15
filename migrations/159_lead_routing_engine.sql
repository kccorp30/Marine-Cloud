-- =========================================================
-- 159_lead_routing_engine.sql — Marine Cloud Phase 11
-- =========================================================
-- Determinístico y auditable: country + region + service_category
-- opcional, mayor especificidad y prioridad ganan, solo
-- organizaciones activas. Sin match -> null (nunca "primera
-- organización activa"). Verificado con datos reales.
-- =========================================================

create or replace function route_website_lead(p_country text, p_region text, p_service_category text)
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select lrr.organization_id
  from lead_routing_rules lrr
  join organizations o on o.id = lrr.organization_id
  where lrr.active = true
    and o.status = 'active'
    and lrr.country = p_country
    and (lrr.region is null or lrr.region = p_region)
    and (lrr.service_category is null or lrr.service_category = p_service_category)
  order by
    (lrr.region is not null)::int desc,
    (lrr.service_category is not null)::int desc,
    lrr.priority asc
  limit 1;
$$;

revoke execute on function route_website_lead(text, text, text) from public, anon;
grant execute on function route_website_lead(text, text, text) to authenticated;

create or replace function manually_route_lead(p_lead_id uuid, p_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lead leads%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can manually route a lead';
  end if;

  select * into v_lead from leads where id = p_lead_id for update;
  if v_lead.id is null then
    raise exception 'lead not found';
  end if;
  if not exists (select 1 from organizations where id = p_organization_id and status = 'active') then
    raise exception 'organization not found or not active';
  end if;

  update leads set assigned_organization_id = p_organization_id, status = 'contacted', updated_at = now()
  where id = p_lead_id;

  perform log_domain_event(p_organization_id, 'WEBSITE_LEAD_ROUTED', 'lead', p_lead_id,
    jsonb_build_object('routed_by', auth.uid(), 'manual', true));
end;
$$;

revoke execute on function manually_route_lead(uuid, uuid) from public, anon;
grant execute on function manually_route_lead(uuid, uuid) to authenticated;
