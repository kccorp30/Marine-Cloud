-- =========================================================
-- 124_notification_rules.sql — Marine Cloud Phase 9
-- =========================================================
-- Mapea domain_events -> notificaciones. organization_id nulo =
-- regla de plataforma. payload_filter es containment jsonb simple —
-- nunca un motor de "ejecutar JSON arbitrario". recipient_strategy es
-- un enum cerrado.
-- =========================================================

create table notification_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references organizations(id),
  event_type text not null,
  payload_filter jsonb,
  severity text not null check (severity in ('info', 'action_required', 'urgent', 'critical')),
  recipient_strategy text not null check (recipient_strategy in ('org_staff', 'assigned_technician', 'customer', 'kcc_admin', 'requesting_technician')),
  title_template text not null,
  body_template text,
  acknowledgement_required boolean not null default false,
  is_active boolean not null default true,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_notification_rules_event_type on notification_rules(event_type, is_active);

alter table notification_rules enable row level security;

create policy "read_notification_rules" on notification_rules for select
using (is_kcc_admin() or organization_id is null or is_org_staff(organization_id));

revoke all on notification_rules from anon, authenticated;
grant select on notification_rules to authenticated;

create or replace function create_notification_rule(
  p_organization_id uuid,
  p_event_type text,
  p_payload_filter jsonb,
  p_severity text,
  p_recipient_strategy text,
  p_title_template text,
  p_body_template text default null,
  p_acknowledgement_required boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_organization_id is null then
    if not is_kcc_admin() then
      raise exception 'only kcc_admin can create platform-wide notification rules';
    end if;
  else
    if not (is_kcc_admin() or exists (
      select 1 from organization_memberships
      where profile_id = auth.uid() and organization_id = p_organization_id and status = 'active'
        and role in ('company_owner', 'company_admin', 'manager')
    )) then
      raise exception 'not authorized to manage notification rules for this organization';
    end if;
  end if;

  insert into notification_rules (organization_id, event_type, payload_filter, severity, recipient_strategy, title_template, body_template, acknowledgement_required, created_by)
  values (p_organization_id, p_event_type, p_payload_filter, p_severity, p_recipient_strategy, p_title_template, p_body_template, p_acknowledgement_required, auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function create_notification_rule(uuid, text, jsonb, text, text, text, text, boolean) from public, anon;
grant execute on function create_notification_rule(uuid, text, jsonb, text, text, text, text, boolean) to authenticated;

create or replace function update_notification_rule(p_rule_id uuid, p_is_active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rule notification_rules%rowtype;
begin
  select * into v_rule from notification_rules where id = p_rule_id;
  if v_rule.id is null then
    raise exception 'rule not found';
  end if;

  if v_rule.organization_id is null then
    if not is_kcc_admin() then
      raise exception 'only kcc_admin can modify platform-wide notification rules';
    end if;
  else
    if not (is_kcc_admin() or exists (
      select 1 from organization_memberships
      where profile_id = auth.uid() and organization_id = v_rule.organization_id and status = 'active'
        and role in ('company_owner', 'company_admin', 'manager')
    )) then
      raise exception 'not authorized to manage notification rules for this organization';
    end if;
  end if;

  update notification_rules set is_active = p_is_active, updated_at = now() where id = p_rule_id;
end;
$$;

revoke execute on function update_notification_rule(uuid, boolean) from public, anon;
grant execute on function update_notification_rule(uuid, boolean) to authenticated;
