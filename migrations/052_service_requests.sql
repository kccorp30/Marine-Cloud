-- =========================================================
-- 052_service_requests.sql — Marine Cloud Phase 4B
-- =========================================================
-- Modelo de intake del customer — deliberadamente NO es un work
-- order. Staff decide explícitamente si/cuándo convertir un pedido en
-- trabajo real (ver convert_service_request_to_work_order en la
-- migración 053) — nunca automático al enviar.
-- =========================================================

create table service_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  customer_id uuid not null,
  vessel_id uuid not null,
  service_category text,
  title text not null,
  description text,
  urgency text not null default 'normal' check (urgency in ('low', 'normal', 'high', 'urgent')),
  preferred_date date,
  preferred_window text,
  status text not null default 'submitted' check (status in ('submitted', 'under_review', 'accepted', 'converted', 'declined', 'cancelled')),
  converted_work_order_id uuid references work_orders(id),
  decline_reason text,
  source text not null default 'marine_cloud',
  client_generated_id uuid not null,
  created_by uuid not null references profiles(id),
  reviewed_by uuid references profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint fk_service_requests_customer_same_org foreign key (customer_id, organization_id) references customers(id, organization_id),
  constraint fk_service_requests_vessel_same_org foreign key (vessel_id, organization_id) references vessels(id, organization_id),
  constraint uq_service_requests_client_generated_id unique (client_generated_id)
);

create index idx_service_requests_org_status on service_requests(organization_id, status, created_at desc);
create index idx_service_requests_customer on service_requests(customer_id, created_at desc);
create index idx_service_requests_vessel on service_requests(vessel_id);

alter table service_requests enable row level security;

create policy "read_service_requests" on service_requests for select
using (
  is_kcc_admin()
  or is_org_staff(organization_id)
  or is_own_customer_record(customer_id)
);

create policy "customer_insert_service_requests" on service_requests for insert
with check (
  is_own_customer_record(customer_id)
  and exists (select 1 from vessels v where v.id = vessel_id and v.current_customer_id = customer_id and v.organization_id = service_requests.organization_id)
  and status = 'submitted'
);

create policy "customer_cancel_own_service_request" on service_requests for update
using (is_own_customer_record(customer_id) and status in ('submitted', 'under_review'))
with check (is_own_customer_record(customer_id) and status = 'cancelled');

create policy "staff_review_service_requests" on service_requests for update
using (is_kcc_admin() or is_org_staff(organization_id))
with check (is_kcc_admin() or is_org_staff(organization_id));

revoke all on service_requests from anon;
grant select, insert, update on service_requests to authenticated;
