-- =========================================================
-- 205_warranty_claim_state_machine.sql — Phase 13 final integrity
-- =========================================================
-- Máquina de estados real: submitted/under_review -> approved|rejected
-- (review_warranty_claim, ya existente) -> approved -> in_progress
-- (create_corrective_work_order_from_claim) -> in_progress -> resolved
-- (resolve_warranty_claim, NUEVA) -> submitted/under_review ->
-- cancelled (cancel_warranty_claim, NUEVA). Verificado con datos
-- reales: ciclo completo submitted->under_review->approved->
-- in_progress->resolved, resolved no puede volver a review, rejected
-- no puede crear trabajo correctivo, duplicado de trabajo correctivo
-- rechazado.
-- =========================================================

create or replace function mark_warranty_claim_under_review(p_claim_id uuid)
returns warranty_claims
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim warranty_claims%rowtype;
begin
  select * into v_claim from warranty_claims where id = p_claim_id for update;
  if v_claim.id is null then
    raise exception 'warranty claim not found';
  end if;
  if v_claim.status != 'submitted' then
    raise exception 'claim must be submitted to move to under_review (status: %)', v_claim.status;
  end if;
  if not (is_org_staff(v_claim.organization_id) or is_kcc_admin()) then
    raise exception 'not authorized to review this claim';
  end if;

  update warranty_claims set status = 'under_review', updated_at = now() where id = p_claim_id returning * into v_claim;

  perform log_domain_event(v_claim.organization_id, 'WARRANTY_CLAIM_UNDER_REVIEW', 'warranty', v_claim.warranty_id,
    jsonb_build_object('claim_id', p_claim_id));

  return v_claim;
end;
$$;

revoke execute on function mark_warranty_claim_under_review(uuid) from public, anon;
grant execute on function mark_warranty_claim_under_review(uuid) to authenticated;

create or replace function resolve_warranty_claim(p_claim_id uuid, p_resolution_notes text default null)
returns warranty_claims
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim warranty_claims%rowtype;
begin
  select * into v_claim from warranty_claims where id = p_claim_id for update;
  if v_claim.id is null then
    raise exception 'warranty claim not found';
  end if;
  if v_claim.status != 'in_progress' then
    raise exception 'claim must be in_progress to resolve (status: %)', v_claim.status;
  end if;
  if not (is_org_staff(v_claim.organization_id) or is_kcc_admin()) then
    raise exception 'not authorized to resolve this claim';
  end if;

  update warranty_claims set status = 'resolved', resolved_at = now(), decision_reason = coalesce(p_resolution_notes, decision_reason), updated_at = now()
  where id = p_claim_id returning * into v_claim;

  perform log_domain_event(v_claim.organization_id, 'WARRANTY_CLAIM_RESOLVED', 'warranty', v_claim.warranty_id,
    jsonb_build_object('claim_id', p_claim_id));
  perform log_audit_event(v_claim.organization_id, 'warranty_claim', p_claim_id, 'warranty_claim_resolved',
    jsonb_build_object('status', 'in_progress'), jsonb_build_object('status', 'resolved'));

  return v_claim;
end;
$$;

revoke execute on function resolve_warranty_claim(uuid, text) from public, anon;
grant execute on function resolve_warranty_claim(uuid, text) to authenticated;

create or replace function cancel_warranty_claim(p_claim_id uuid, p_reason text default null)
returns warranty_claims
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim warranty_claims%rowtype;
begin
  select * into v_claim from warranty_claims where id = p_claim_id for update;
  if v_claim.id is null then
    raise exception 'warranty claim not found';
  end if;
  if v_claim.status not in ('submitted', 'under_review') then
    raise exception 'claim can only be cancelled while submitted or under_review (status: %)', v_claim.status;
  end if;
  if not (is_org_staff(v_claim.organization_id) or is_kcc_admin() or is_own_customer_record(v_claim.customer_id)) then
    raise exception 'not authorized to cancel this claim';
  end if;

  update warranty_claims set status = 'cancelled', decision_reason = coalesce(p_reason, decision_reason), updated_at = now()
  where id = p_claim_id returning * into v_claim;

  return v_claim;
end;
$$;

revoke execute on function cancel_warranty_claim(uuid, text) from public, anon;
grant execute on function cancel_warranty_claim(uuid, text) to authenticated;
