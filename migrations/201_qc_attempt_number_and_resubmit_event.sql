-- =========================================================
-- 201_qc_attempt_number_and_resubmit_event.sql — Phase 13 final
-- =========================================================
-- attempt_number: contador real por work order. QC_RESUBMITTED se
-- emite en vez de QC_STARTED cuando ya existe un intento previo —
-- hechos de negocio distintos.
-- Verificado con datos reales: attempt_number incrementa a 2 tras un
-- fallo + reinicio, QC_RESUBMITTED emitido exactamente una vez,
-- QC_STARTED solo en el primer intento.
-- =========================================================

alter table qc_submissions add column attempt_number int not null default 1;

create or replace function start_qc_submission(p_work_order_id uuid, p_items jsonb)
returns qc_submissions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders%rowtype;
  v_submission qc_submissions%rowtype;
  v_item jsonb;
  v_prior_count int;
begin
  select * into v_wo from work_orders where id = p_work_order_id;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;
  if not exists (select 1 from organizations where id = v_wo.organization_id and status = 'active') then
    raise exception 'organization is not active';
  end if;
  if not (is_org_staff(v_wo.organization_id) or is_assigned_to_work_order(p_work_order_id)) then
    raise exception 'not authorized to start QC for this work order';
  end if;
  if v_wo.current_status != 'quality_control' then
    raise exception 'work order must be in quality_control status to start QC (current: %)', v_wo.current_status;
  end if;

  select count(*) into v_prior_count from qc_submissions where work_order_id = p_work_order_id;

  insert into qc_submissions (organization_id, work_order_id, submitted_by, status, attempt_number)
  values (v_wo.organization_id, p_work_order_id, auth.uid(), 'draft', v_prior_count + 1)
  returning * into v_submission;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    insert into qc_submission_items (qc_submission_id, label, required, sort_order)
    values (v_submission.id, v_item->>'label', coalesce((v_item->>'required')::boolean, true), coalesce((v_item->>'sortOrder')::int, 0));
  end loop;

  perform log_domain_event(v_wo.organization_id, case when v_prior_count = 0 then 'QC_STARTED' else 'QC_RESUBMITTED' end, 'work_order', p_work_order_id,
    jsonb_build_object('qc_submission_id', v_submission.id, 'attempt_number', v_submission.attempt_number));

  return v_submission;
end;
$$;
