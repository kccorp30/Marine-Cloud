-- =========================================================
-- 141_compensation_agreements.sql — Marine Cloud Phase 10
-- =========================================================
-- percentage exige percentage_rate (sin fixed_amount), fixed exige
-- fixed_amount (sin percentage_rate) — CHECK constraint real. numeric
-- para todo lo monetario. Nunca se sobreescribe una vigencia
-- histórica. Verificado con datos reales: percentage válido,
-- percentage+fixed_amount rechazado, solapamiento rechazado,
-- company_owner no puede leer ni crear.
-- =========================================================

create table compensation_agreements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  compensation_type text not null check (compensation_type in ('percentage', 'fixed')),
  percentage_rate numeric(6,3),
  fixed_amount numeric(12,2),
  currency text not null default 'USD',
  effective_from date not null,
  effective_until date,
  active boolean not null default true,
  notes text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint chk_compensation_type_fields check (
    (compensation_type = 'percentage' and percentage_rate is not null and fixed_amount is null and percentage_rate > 0 and percentage_rate <= 100)
    or
    (compensation_type = 'fixed' and fixed_amount is not null and percentage_rate is null and fixed_amount > 0)
  ),
  constraint chk_effective_range check (effective_until is null or effective_until >= effective_from)
);

create index idx_compensation_agreements_org on compensation_agreements(organization_id, effective_from);

alter table compensation_agreements enable row level security;

create policy "read_compensation_agreements" on compensation_agreements for select
using (is_kcc_admin());

revoke all on compensation_agreements from anon, authenticated;
grant select on compensation_agreements to authenticated;

create or replace function create_compensation_agreement(
  p_organization_id uuid,
  p_compensation_type text,
  p_percentage_rate numeric default null,
  p_fixed_amount numeric default null,
  p_currency text default 'USD',
  p_effective_from date default current_date,
  p_effective_until date default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_overlap_exists boolean;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can create compensation agreements';
  end if;
  if not exists (select 1 from organizations where id = p_organization_id) then
    raise exception 'organization not found';
  end if;

  select exists (
    select 1 from compensation_agreements
    where organization_id = p_organization_id
      and active = true
      and effective_from <= coalesce(p_effective_until, 'infinity'::date)
      and coalesce(effective_until, 'infinity'::date) >= p_effective_from
  ) into v_overlap_exists;

  if v_overlap_exists then
    raise exception 'an active compensation agreement already covers part of this effective period for this organization';
  end if;

  insert into compensation_agreements (organization_id, compensation_type, percentage_rate, fixed_amount, currency, effective_from, effective_until, notes, created_by)
  values (p_organization_id, p_compensation_type, p_percentage_rate, p_fixed_amount, p_currency, p_effective_from, p_effective_until, p_notes, auth.uid())
  returning id into v_id;

  perform log_domain_event(p_organization_id, 'COMPENSATION_AGREEMENT_CREATED', 'compensation_agreement', v_id,
    jsonb_build_object('compensation_type', p_compensation_type, 'effective_from', p_effective_from));
  perform log_audit_event(p_organization_id, 'compensation_agreement', v_id, 'compensation_agreement_created',
    null, jsonb_build_object('compensation_type', p_compensation_type));

  return v_id;
end;
$$;

revoke execute on function create_compensation_agreement(uuid, text, numeric, numeric, text, date, date, text) from public, anon;
grant execute on function create_compensation_agreement(uuid, text, numeric, numeric, text, date, date, text) to authenticated;

create or replace function deactivate_compensation_agreement(p_agreement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agreement compensation_agreements%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can change compensation agreements';
  end if;

  select * into v_agreement from compensation_agreements where id = p_agreement_id;
  if v_agreement.id is null then
    raise exception 'agreement not found';
  end if;

  update compensation_agreements set active = false, updated_at = now() where id = p_agreement_id;

  perform log_domain_event(v_agreement.organization_id, 'COMPENSATION_AGREEMENT_CHANGED', 'compensation_agreement', p_agreement_id,
    jsonb_build_object('action', 'deactivated'));
  perform log_audit_event(v_agreement.organization_id, 'compensation_agreement', p_agreement_id, 'compensation_agreement_deactivated',
    jsonb_build_object('active', true), jsonb_build_object('active', false));
end;
$$;

revoke execute on function deactivate_compensation_agreement(uuid) from public, anon;
grant execute on function deactivate_compensation_agreement(uuid) to authenticated;
