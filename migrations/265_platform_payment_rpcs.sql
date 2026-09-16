-- =========================================================
-- 265_platform_payment_rpcs.sql — Marine Cloud Phase 15
-- =========================================================
-- record_manual_platform_payment (KCC), submit_platform_payment_proof
-- (company, siempre pending_verification, nunca auto-verified),
-- add_platform_payment_evidence (inmutable tras verificación).
-- =========================================================

create or replace function record_manual_platform_payment(
  p_organization_id uuid, p_payment_method_id uuid, p_amount numeric, p_currency text,
  p_received_at timestamptz, p_reference text default null, p_notes text default null
)
returns platform_payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment platform_payments%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can record a payment directly';
  end if;
  if p_amount <= 0 then
    raise exception 'payment amount must be positive';
  end if;
  if not exists (select 1 from platform_payment_methods where id = p_payment_method_id and active = true) then
    raise exception 'payment method not found or inactive';
  end if;

  insert into platform_payments (organization_id, payment_method_id, provider, amount, currency, status, reference, received_at, recorded_by, notes)
  values (p_organization_id, p_payment_method_id, 'manual', p_amount, coalesce(p_currency, 'USD'), 'pending_verification', p_reference, p_received_at, auth.uid(), p_notes)
  returning * into v_payment;

  perform log_domain_event(p_organization_id, 'PLATFORM_PAYMENT_SUBMITTED', 'organization', p_organization_id,
    jsonb_build_object('payment_id', v_payment.id, 'amount', p_amount, 'method_id', p_payment_method_id, 'recorded_by_kcc', true));
  perform log_audit_event(p_organization_id, 'platform_payment', v_payment.id, 'payment_recorded_by_kcc', null, to_jsonb(v_payment));

  return v_payment;
end;
$$;

revoke execute on function record_manual_platform_payment(uuid, uuid, numeric, text, timestamptz, text, text) from public, anon;
grant execute on function record_manual_platform_payment(uuid, uuid, numeric, text, timestamptz, text, text) to authenticated;

create or replace function submit_platform_payment_proof(
  p_organization_id uuid, p_payment_method_id uuid, p_amount numeric, p_currency text,
  p_reference text default null, p_notes text default null
)
returns platform_payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_role text;
  v_payment platform_payments%rowtype;
  v_method platform_payment_methods%rowtype;
begin
  select role into v_actor_role from organization_memberships
  where profile_id = auth.uid() and organization_id = p_organization_id and status = 'active';
  if v_actor_role not in ('company_owner', 'company_admin') and not is_kcc_admin() then
    raise exception 'only the company owner/admin can submit payment evidence for their own organization';
  end if;
  if p_amount <= 0 then
    raise exception 'payment amount must be positive';
  end if;

  select * into v_method from platform_payment_methods where id = p_payment_method_id and active = true;
  if v_method.id is null then
    raise exception 'payment method not found or inactive';
  end if;
  if v_method.requires_reference and (p_reference is null or trim(p_reference) = '') then
    raise exception 'this payment method requires a reference';
  end if;

  insert into platform_payments (organization_id, payment_method_id, provider, amount, currency, status, reference, received_at, recorded_by, submitted_by_role, notes)
  values (p_organization_id, p_payment_method_id, 'manual', p_amount, coalesce(p_currency, 'USD'), 'pending_verification', p_reference, now(), auth.uid(), v_actor_role, p_notes)
  returning * into v_payment;

  perform log_domain_event(p_organization_id, 'PLATFORM_PAYMENT_SUBMITTED', 'organization', p_organization_id,
    jsonb_build_object('payment_id', v_payment.id, 'amount', p_amount, 'method_id', p_payment_method_id, 'recorded_by_kcc', false));
  perform log_audit_event(p_organization_id, 'platform_payment', v_payment.id, 'payment_proof_submitted', null, to_jsonb(v_payment));

  return v_payment;
end;
$$;

revoke execute on function submit_platform_payment_proof(uuid, uuid, numeric, text, text, text) from public, anon;
grant execute on function submit_platform_payment_proof(uuid, uuid, numeric, text, text, text) to authenticated;

create or replace function add_platform_payment_evidence(p_payment_id uuid, p_storage_path text, p_mime_type text default null)
returns platform_payment_evidence
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment platform_payments%rowtype;
  v_actor_role text;
  v_evidence platform_payment_evidence%rowtype;
begin
  select * into v_payment from platform_payments where id = p_payment_id;
  if v_payment.id is null then
    raise exception 'payment not found';
  end if;
  select role into v_actor_role from organization_memberships
  where profile_id = auth.uid() and organization_id = v_payment.organization_id and status = 'active';
  if v_actor_role not in ('company_owner', 'company_admin') and not is_kcc_admin() then
    raise exception 'not authorized to attach evidence to this payment';
  end if;
  if v_payment.status = 'verified' and not is_kcc_admin() then
    raise exception 'cannot modify evidence on an already-verified payment';
  end if;

  insert into platform_payment_evidence (organization_id, payment_id, storage_path, mime_type, uploaded_by)
  values (v_payment.organization_id, p_payment_id, p_storage_path, p_mime_type, auth.uid())
  returning * into v_evidence;

  return v_evidence;
end;
$$;

revoke execute on function add_platform_payment_evidence(uuid, text, text) from public, anon;
grant execute on function add_platform_payment_evidence(uuid, text, text) to authenticated;
