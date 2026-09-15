-- =========================================================
-- 195_warranty_claims_rpcs.sql — Marine Cloud Phase 13
-- =========================================================
-- Elegibilidad SIEMPRE compara fecha actual contra starts_at/ends_at
-- real, nunca confía solo en status. Verificado con datos reales:
-- customer dueño puede reclamar, no relacionado rechazado, org no
-- autorizada rechazada en revisión, staff real aprueba, garantía
-- vencida rechaza reclamos nuevos.
-- =========================================================

create or replace function submit_warranty_claim(
  p_warranty_id uuid,
  p_reason text,
  p_description text default null
)
returns warranty_claims
language plpgsql
security definer
set search_path = public
as $$
declare
  v_warranty warranties%rowtype;
  v_claim warranty_claims%rowtype;
begin
  select * into v_warranty from warranties where id = p_warranty_id;
  if v_warranty.id is null then
    raise exception 'warranty not found';
  end if;

  if not (is_own_customer_record(v_warranty.customer_id) or is_org_staff(v_warranty.organization_id) or is_kcc_admin()) then
    raise exception 'not authorized to submit a claim for this warranty';
  end if;

  if not exists (select 1 from organizations where id = v_warranty.organization_id and status = 'active') then
    raise exception 'organization is not active';
  end if;
  if v_warranty.status = 'voided' then
    raise exception 'this warranty has been voided and cannot accept new claims';
  end if;
  if v_warranty.ends_at is null or v_warranty.ends_at < current_date then
    raise exception 'this warranty has expired and cannot accept new claims';
  end if;
  if v_warranty.starts_at is null or v_warranty.starts_at > current_date then
    raise exception 'this warranty has not started yet';
  end if;
  if p_reason is null or trim(p_reason) = '' then
    raise exception 'a reason is required';
  end if;

  insert into warranty_claims (organization_id, warranty_id, customer_id, vessel_id, original_work_order_id, reason, description, status)
  values (v_warranty.organization_id, p_warranty_id, v_warranty.customer_id, v_warranty.vessel_id, v_warranty.work_order_id, p_reason, p_description, 'submitted')
  returning * into v_claim;

  perform log_domain_event(v_warranty.organization_id, 'WARRANTY_CLAIM_SUBMITTED', 'warranty', p_warranty_id,
    jsonb_build_object('claim_id', v_claim.id));

  return v_claim;
end;
$$;

revoke execute on function submit_warranty_claim(uuid, text, text) from public, anon;
grant execute on function submit_warranty_claim(uuid, text, text) to authenticated;

create or replace function review_warranty_claim(p_claim_id uuid, p_decision text, p_decision_reason text default null)
returns warranty_claims
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim warranty_claims%rowtype;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'decision must be approved or rejected';
  end if;

  select * into v_claim from warranty_claims where id = p_claim_id for update;
  if v_claim.id is null then
    raise exception 'warranty claim not found';
  end if;
  if v_claim.status not in ('submitted', 'under_review') then
    raise exception 'claim is not awaiting review (status: %)', v_claim.status;
  end if;
  if not (is_org_staff(v_claim.organization_id) or is_kcc_admin()) then
    raise exception 'not authorized to review this claim';
  end if;

  update warranty_claims set status = p_decision, reviewed_by = auth.uid(), reviewed_at = now(), decision_reason = p_decision_reason, updated_at = now()
  where id = p_claim_id returning * into v_claim;

  perform log_domain_event(v_claim.organization_id, case when p_decision = 'approved' then 'WARRANTY_CLAIM_APPROVED' else 'WARRANTY_CLAIM_REJECTED' end,
    'warranty', v_claim.warranty_id, jsonb_build_object('claim_id', p_claim_id, 'decision_reason', p_decision_reason));
  perform log_audit_event(v_claim.organization_id, 'warranty_claim', p_claim_id, 'warranty_claim_' || p_decision,
    jsonb_build_object('status', 'submitted'), jsonb_build_object('status', p_decision));

  return v_claim;
end;
$$;

revoke execute on function review_warranty_claim(uuid, text, text) from public, anon;
grant execute on function review_warranty_claim(uuid, text, text) to authenticated;
