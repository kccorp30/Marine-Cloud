-- =========================================================
-- 156_website_lead_conversion_schema.sql — Marine Cloud Phase 11
-- =========================================================
-- Paso 0 (reportado): el sitio KCCORP y Marine Cloud comparten el
-- MISMO proyecto de Supabase. La tabla `leads` YA es el registro
-- durable de idempotencia — se reusa tal cual, sin crear
-- website_lead_conversions duplicada. work_orders.source y
-- work_orders.website_lead_id YA existían pero sin FK real — se
-- agrega acá. service_requests no tenía website_lead_id — se agrega,
-- siguiendo el flujo preferido lead -> customer -> vessel ->
-- service_request -> (luego) work_order vía el camino ya existente,
-- nunca bypasseando transition_work_order().
-- =========================================================

alter table work_orders add constraint fk_work_orders_website_lead foreign key (website_lead_id) references leads(id);
alter table service_requests add column website_lead_id uuid references leads(id);

create table lead_routing_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  country text not null,
  region text,
  service_category text,
  priority int not null default 100,
  active boolean not null default true,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_lead_routing_rules_lookup on lead_routing_rules(country, active, priority);

alter table lead_routing_rules enable row level security;

create policy "read_lead_routing_rules" on lead_routing_rules for select
using (is_kcc_admin());

revoke all on lead_routing_rules from anon, authenticated;
grant select on lead_routing_rules to authenticated;

create or replace function create_lead_routing_rule(
  p_organization_id uuid,
  p_country text,
  p_region text default null,
  p_service_category text default null,
  p_priority int default 100
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can create lead routing rules';
  end if;
  if not exists (select 1 from organizations where id = p_organization_id and status = 'active') then
    raise exception 'organization not found or not active';
  end if;

  insert into lead_routing_rules (organization_id, country, region, service_category, priority, created_by)
  values (p_organization_id, p_country, p_region, p_service_category, p_priority, auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function create_lead_routing_rule(uuid, text, text, text, int) from public, anon;
grant execute on function create_lead_routing_rule(uuid, text, text, text, int) to authenticated;
