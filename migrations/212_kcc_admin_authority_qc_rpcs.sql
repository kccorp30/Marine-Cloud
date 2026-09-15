-- =========================================================
-- 212_kcc_admin_authority_qc_rpcs.sql — Phase 13 true final closure
-- =========================================================
-- Mismo fix para las 4 RPCs de QC restantes.
-- =========================================================

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
  if not (is_org_staff(v_wo.organization_id) or is_assigned_to_work_order(p_work_order_id) or is_kcc_admin()) then
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

create or replace function set_qc_item_result(p_item_id uuid, p_result text, p_notes text default null, p_media_asset_id uuid default null)
returns qc_submission_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item qc_submission_items%rowtype;
  v_submission qc_submissions%rowtype;
begin
  if p_result not in ('pending', 'pass', 'fail', 'not_applicable') then
    raise exception 'invalid result: %', p_result;
  end if;

  select * into v_item from qc_submission_items where id = p_item_id;
  if v_item.id is null then
    raise exception 'QC item not found';
  end if;
  select * into v_submission from qc_submissions where id = v_item.qc_submission_id;
  if v_submission.status != 'draft' then
    raise exception 'QC submission is no longer editable (status: %)', v_submission.status;
  end if;
  if not (is_org_staff(v_submission.organization_id) or is_assigned_to_work_order(v_submission.work_order_id) or is_kcc_admin()) then
    raise exception 'not authorized to edit this QC item';
  end if;

  update qc_submission_items set result = p_result, notes = coalesce(p_notes, notes), media_asset_id = coalesce(p_media_asset_id, media_asset_id)
  where id = p_item_id
  returning * into v_item;

  return v_item;
end;
$$;

create or replace function submit_qc_for_review(p_submission_id uuid)
returns qc_submissions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_submission qc_submissions%rowtype;
  v_unresolved_count int;
begin
  select * into v_submission from qc_submissions where id = p_submission_id;
  if v_submission.id is null then
    raise exception 'QC submission not found';
  end if;
  if v_submission.status != 'draft' then
    raise exception 'QC submission is not in draft (status: %)', v_submission.status;
  end if;
  if not (is_org_staff(v_submission.organization_id) or is_assigned_to_work_order(v_submission.work_order_id) or is_kcc_admin()) then
    raise exception 'not authorized to submit this QC';
  end if;

  select count(*) into v_unresolved_count from qc_submission_items
  where qc_submission_id = p_submission_id and required = true and result = 'pending';
  if v_unresolved_count > 0 then
    raise exception 'cannot submit — % required item(s) still pending', v_unresolved_count;
  end if;

  update qc_submissions set status = 'submitted', submitted_at = now(), updated_at = now()
  where id = p_submission_id returning * into v_submission;

  perform log_domain_event(v_submission.organization_id, 'QC_SUBMITTED', 'work_order', v_submission.work_order_id,
    jsonb_build_object('qc_submission_id', p_submission_id));

  return v_submission;
end;
$$;

create or replace function attach_qc_evidence(p_item_id uuid, p_media_asset_id uuid)
returns qc_evidence
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item qc_submission_items%rowtype;
  v_submission qc_submissions%rowtype;
  v_media media_assets%rowtype;
  v_evidence qc_evidence%rowtype;
begin
  select * into v_item from qc_submission_items where id = p_item_id;
  if v_item.id is null then
    raise exception 'QC item not found';
  end if;
  select * into v_submission from qc_submissions where id = v_item.qc_submission_id;
  if v_submission.status != 'draft' then
    raise exception 'QC submission is no longer editable (status: %)', v_submission.status;
  end if;
  if not (is_org_staff(v_submission.organization_id) or is_assigned_to_work_order(v_submission.work_order_id) or is_kcc_admin()) then
    raise exception 'not authorized to attach evidence to this QC item';
  end if;

  select * into v_media from media_assets where id = p_media_asset_id;
  if v_media.id is null then
    raise exception 'media asset not found';
  end if;
  if v_media.organization_id != v_submission.organization_id or v_media.work_order_id != v_submission.work_order_id then
    raise exception 'media asset does not belong to this work order';
  end if;

  insert into qc_evidence (organization_id, qc_submission_item_id, media_asset_id, added_by)
  values (v_submission.organization_id, p_item_id, p_media_asset_id, auth.uid())
  on conflict (qc_submission_item_id, media_asset_id) do nothing
  returning * into v_evidence;

  if v_evidence.id is null then
    select * into v_evidence from qc_evidence where qc_submission_item_id = p_item_id and media_asset_id = p_media_asset_id;
  end if;

  return v_evidence;
end;
$$;
