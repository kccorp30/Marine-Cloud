-- =========================================================
-- 215_warranty_claim_cancelled_event.sql — Phase 13 last correctness pass
-- =========================================================
-- GAP REAL: cancel_warranty_claim() cambiaba el status a 'cancelled'
-- pero nunca emitía evidencia de dominio/auditoría. WARRANTY_CLAIM_
-- CANCELLED es un nombre nuevo, no duplica ninguno existente.
-- Autorización de cancelación sin cambios.
-- NOTA: esta versión tenía un bug real (usaba log_audit_event() en
-- vez de log_audit_event_internal()) — corregido en 216 aplicada
-- inmediatamente después.
-- =========================================================

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

  perform log_domain_event(v_claim.organization_id, 'WARRANTY_CLAIM_CANCELLED', 'warranty', v_claim.warranty_id,
    jsonb_build_object('claim_id', p_claim_id, 'reason', p_reason));
  perform log_audit_event(v_claim.organization_id, 'warranty_claim', p_claim_id, 'warranty_claim_cancelled',
    jsonb_build_object('status', 'submitted_or_under_review'), jsonb_build_object('status', 'cancelled', 'reason', p_reason));

  return v_claim;
end;
$$;
