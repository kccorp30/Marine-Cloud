-- =========================================================
-- 010_domain_and_audit_events.sql — Marine Cloud Phase 0
-- =========================================================
-- Domain events: acontecimientos operativos (WORK_ORDER_CREATED, etc.)
-- Audit events: cambios sensibles, inmutable, para compliance.
-- Separados a propósito (ADR-010) — nunca se mezclan.

create table domain_events (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references organizations(id),
  event_type        text not null,
  entity_type       text not null,
  entity_id         uuid not null,
  payload           jsonb not null default '{}'::jsonb,
  actor_profile_id  uuid references profiles(id),  -- null = sistema/automatización
  occurred_at       timestamptz not null default now()
);

create index idx_domain_events_org_time on domain_events(organization_id, occurred_at desc);
create index idx_domain_events_entity on domain_events(entity_type, entity_id);
create index idx_domain_events_type on domain_events(event_type);

alter table domain_events enable row level security;

-- INSERT solo vía función SECURITY DEFINER — nunca insert directo del
-- cliente. Esto evita que un usuario falsifique el historial de eventos.
create or replace function log_domain_event(
  p_organization_id uuid,
  p_event_type text,
  p_entity_type text,
  p_entity_id uuid,
  p_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into domain_events (organization_id, event_type, entity_type, entity_id, payload, actor_profile_id)
  values (p_organization_id, p_event_type, p_entity_type, p_entity_id, p_payload, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

-- Cualquier usuario autenticado puede EJECUTAR la función (la propia
-- función decide qué se registra), pero nadie puede hacer INSERT
-- directo a la tabla — no hay policy de INSERT en domain_events.
grant execute on function log_domain_event(uuid, text, text, uuid, jsonb) to authenticated;

-- ---------------------------------------------------------
-- audit_events — inmutable, sensible
-- ---------------------------------------------------------
create table audit_events (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid references organizations(id),  -- null para acciones cross-tenant de KCC
  actor_profile_id  uuid references profiles(id),
  entity_type       text not null,
  entity_id         uuid not null,
  action            text not null,
  before            jsonb,
  after             jsonb,
  occurred_at       timestamptz not null default now()
);

create index idx_audit_events_org_time on audit_events(organization_id, occurred_at desc);
create index idx_audit_events_entity on audit_events(entity_type, entity_id);

alter table audit_events enable row level security;

create or replace function log_audit_event(
  p_organization_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_action text,
  p_before jsonb default null,
  p_after jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into audit_events (organization_id, actor_profile_id, entity_type, entity_id, action, before, after)
  values (p_organization_id, auth.uid(), p_entity_type, p_entity_id, p_action, p_before, p_after)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function log_audit_event(uuid, text, uuid, text, jsonb, jsonb) to authenticated;

-- Trigger genérico reusable: cualquier tabla futura puede adoptar este
-- patrón para auto-auditar UPDATEs sensibles sin código de aplicación
-- adicional. Ejemplo de uso ya aplicado abajo a organization_memberships
-- (cambio de rol) y organizations (cambio de status).
--
-- NOTA: la versión original de este trigger tenía un bug (asumía que
-- toda tabla auditada tiene columna organization_id) — corregido en
-- 015_fix_audit_trigger_generic.sql. La definición de abajo es la
-- ORIGINAL tal como se corrió, a propósito, para preservar el
-- historial real — no la reescribas aquí.
create or replace function trg_audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform log_audit_event(
    coalesce(new.organization_id, old.organization_id),
    TG_TABLE_NAME,
    coalesce(new.id, old.id),
    TG_OP,
    to_jsonb(old),
    to_jsonb(new)
  );
  return new;
end;
$$;

create trigger trg_audit_organization_memberships
  after update on organization_memberships
  for each row
  when (old.role is distinct from new.role or old.status is distinct from new.status)
  execute function trg_audit_row_change();

create trigger trg_audit_organizations
  after update on organizations
  for each row
  when (old.status is distinct from new.status)
  execute function trg_audit_row_change();
