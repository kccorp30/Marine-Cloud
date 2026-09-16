-- =========================================================
-- 128_kcc_assistance_schema.sql — Marine Cloud Phase 9
-- =========================================================
-- Estado explícito y cerrado — nunca texto libre. Máquina de estados
-- real: open -> accepted -> started -> resolved, escalated alcanzable
-- desde open/accepted/started. Nunca open->started directo.
-- Verificado: técnico asignado puede pedir, no asignado no puede,
-- todo derivado server-side.
--
-- NOTA: esta versión llama a log_audit_event() (exige is_org_staff) —
-- pero quien llama es un TÉCNICO, no staff. Bug real encontrado
-- probando esta función, corregido en la migración 131 aplicada por
-- separado inmediatamente después. Se deja este archivo tal cual se
-- aplicó, reflejando el historial real.
-- =========================================================

create table kcc_assistance_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  requesting_technician_id uuid not null references profiles(id),
  work_order_id uuid not null references work_orders(id),
  vessel_id uuid references vessels(id),
  current_job_status text,
  category text not null check (category in ('parts', 'technical', 'access', 'safety', 'scheduling', 'other')),
  urgency text not null default 'normal' check (urgency in ('normal', 'high', 'critical')),
  notes text,
  status text not null default 'open' check (status in ('open', 'accepted', 'started', 'resolved', 'escalated')),
  accepted_by uuid references profiles(id),
  accepted_at timestamptz,
  started_at timestamptz,
  resolved_at timestamptz,
  escalated_at timestamptz,
  resolution_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table kcc_assistance_requests add constraint uq_kcc_assistance_id_org unique (id, organization_id);
alter table kcc_assistance_requests add constraint fk_kcc_assistance_wo_same_org
  foreign key (work_order_id, organization_id) references work_orders(id, organization_id) not valid;
alter table kcc_assistance_requests validate constraint fk_kcc_assistance_wo_same_org;

create index idx_kcc_assistance_org_status on kcc_assistance_requests(organization_id, status, created_at desc);
create index idx_kcc_assistance_open on kcc_assistance_requests(status, created_at) where status in ('open', 'accepted', 'started');

alter table kcc_assistance_requests enable row level security;

create policy "read_kcc_assistance" on kcc_assistance_requests for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or requesting_technician_id = auth.uid()
);

revoke all on kcc_assistance_requests from anon, authenticated;
grant select on kcc_assistance_requests to authenticated;

create or replace function request_kcc_assistance(
  p_work_order_id uuid,
  p_category text,
  p_urgency text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders%rowtype;
  v_request_id uuid;
begin
  select * into v_wo from work_orders where id = p_work_order_id;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;
  if not is_assigned_to_work_order(p_work_order_id) then
    raise exception 'only the technician assigned to this work order can request KCC assistance for it';
  end if;

  insert into kcc_assistance_requests (
    organization_id, requesting_technician_id, work_order_id, vessel_id,
    current_job_status, category, urgency, notes
  )
  values (
    v_wo.organization_id, auth.uid(), p_work_order_id, v_wo.vessel_id,
    v_wo.current_status, p_category, p_urgency, p_notes
  )
  returning id into v_request_id;

  perform log_domain_event(v_wo.organization_id, 'KCC_ASSISTANCE_REQUESTED', 'kcc_assistance_request', v_request_id,
    jsonb_build_object('work_order_id', p_work_order_id, 'category', p_category, 'urgency', p_urgency));
  perform log_audit_event(v_wo.organization_id, 'kcc_assistance_request', v_request_id, 'kcc_assistance_requested',
    null, jsonb_build_object('category', p_category, 'urgency', p_urgency));

  return v_request_id;
end;
$$;

revoke execute on function request_kcc_assistance(uuid, text, text, text) from public, anon;
grant execute on function request_kcc_assistance(uuid, text, text, text) to authenticated;
