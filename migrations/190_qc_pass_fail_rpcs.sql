-- =========================================================
-- 190_qc_pass_fail_rpcs.sql — Marine Cloud Phase 13
-- =========================================================
-- PASS exige can_review_qc() + nunca el mismo submitted_by salvo
-- kcc_admin + ningún item requerido sin resolver como pass/n.a.
-- Verificado con datos reales: auto-aprobación bloqueada, manager
-- distinto pasa correctamente, fail registra motivo real.
-- =========================================================

create or replace function pass_qc_submission(p_submission_id uuid, p_notes text default null)
returns qc_submissions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_submission qc_submissions%rowtype;
  v_unresolved_count int;
begin
  select * into v_submission from qc_submissions where id = p_submission_id for update;
  if v_submission.id is null then
    raise exception 'QC submission not found';
  end if;
  if v_submission.status != 'submitted' then
    raise exception 'QC submission is not awaiting review (status: %)', v_submission.status;
  end if;
  if not can_review_qc(v_submission.organization_id) then
    raise exception 'not authorized to review QC for this organization';
  end if;
  if not exists (select 1 from organizations where id = v_submission.organization_id and status = 'active') then
    raise exception 'organization is not active';
  end if;

  if v_submission.submitted_by = auth.uid() and not is_kcc_admin() then
    raise exception 'the technician who submitted this QC cannot approve their own review';
  end if;

  select count(*) into v_unresolved_count from qc_submission_items
  where qc_submission_id = p_submission_id and required = true and result not in ('pass', 'not_applicable');
  if v_unresolved_count > 0 then
    raise exception 'cannot pass — % required item(s) not resolved as pass/not_applicable', v_unresolved_count;
  end if;

  update qc_submissions set status = 'passed', reviewed_by = auth.uid(), reviewed_at = now(), passed_at = now(), notes = coalesce(p_notes, notes), updated_at = now()
  where id = p_submission_id returning * into v_submission;

  perform log_domain_event(v_submission.organization_id, 'QC_PASSED', 'work_order', v_submission.work_order_id,
    jsonb_build_object('qc_submission_id', p_submission_id, 'reviewed_by', auth.uid()));
  perform log_audit_event(v_submission.organization_id, 'qc_submission', p_submission_id, 'qc_passed',
    jsonb_build_object('status', 'submitted'), jsonb_build_object('status', 'passed', 'reviewed_by', auth.uid()));

  return v_submission;
end;
$$;

revoke execute on function pass_qc_submission(uuid, text) from public, anon;
grant execute on function pass_qc_submission(uuid, text) to authenticated;

create or replace function fail_qc_submission(p_submission_id uuid, p_failure_reason text, p_notes text default null)
returns qc_submissions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_submission qc_submissions%rowtype;
begin
  select * into v_submission from qc_submissions where id = p_submission_id for update;
  if v_submission.id is null then
    raise exception 'QC submission not found';
  end if;
  if v_submission.status != 'submitted' then
    raise exception 'QC submission is not awaiting review (status: %)', v_submission.status;
  end if;
  if not can_review_qc(v_submission.organization_id) then
    raise exception 'not authorized to review QC for this organization';
  end if;
  if v_submission.submitted_by = auth.uid() and not is_kcc_admin() then
    raise exception 'the technician who submitted this QC cannot review their own submission';
  end if;
  if p_failure_reason is null or trim(p_failure_reason) = '' then
    raise exception 'failure_reason is required';
  end if;

  update qc_submissions set status = 'failed', reviewed_by = auth.uid(), reviewed_at = now(), failed_at = now(), failure_reason = p_failure_reason, notes = coalesce(p_notes, notes), updated_at = now()
  where id = p_submission_id returning * into v_submission;

  perform log_domain_event(v_submission.organization_id, 'QC_FAILED', 'work_order', v_submission.work_order_id,
    jsonb_build_object('qc_submission_id', p_submission_id, 'reviewed_by', auth.uid(), 'failure_reason', p_failure_reason));
  perform log_audit_event(v_submission.organization_id, 'qc_submission', p_submission_id, 'qc_failed',
    jsonb_build_object('status', 'submitted'), jsonb_build_object('status', 'failed', 'failure_reason', p_failure_reason));

  return v_submission;
end;
$$;

revoke execute on function fail_qc_submission(uuid, text, text) from public, anon;
grant execute on function fail_qc_submission(uuid, text, text) to authenticated;
