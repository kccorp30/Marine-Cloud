-- =========================================================
-- 189_qc_lifecycle_rpcs.sql — Marine Cloud Phase 13
-- =========================================================
-- can_review_qc() centraliza la autoridad: company_admin/manager/
-- kcc_admin revisan. technician prepara/submite, nunca aprueba.
-- Verificado con datos reales: técnico no tiene autoridad de
-- revisión, manager sí.
-- =========================================================

create or replace function can_review_qc(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select is_kcc_admin() or exists (
    select 1 from organization_memberships
    where profile_id = auth.uid() and organization_id = p_organization_id and status = 'active'
      and role in ('company_admin', 'manager')
  );
$$;

revoke execute on function can_review_qc(uuid) from public, anon;
grant execute on function can_review_qc(uuid) to authenticated;

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

  insert into qc_submissions (organization_id, work_order_id, submitted_by, status)
  values (v_wo.organization_id, p_work_order_id, auth.uid(), 'draft')
  returning * into v_submission;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    insert into qc_submission_items (qc_submission_id, label, required, sort_order)
    values (v_submission.id, v_item->>'label', coalesce((v_item->>'required')::boolean, true), coalesce((v_item->>'sortOrder')::int, 0));
  end loop;

  perform log_domain_event(v_wo.organization_id, 'QC_STARTED', 'work_order', p_work_order_id,
    jsonb_build_object('qc_submission_id', v_submission.id));

  return v_submission;
end;
$$;

revoke execute on function start_qc_submission(uuid, jsonb) from public, anon;
grant execute on function start_qc_submission(uuid, jsonb) to authenticated;

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
  if not (is_org_staff(v_submission.organization_id) or is_assigned_to_work_order(v_submission.work_order_id)) then
    raise exception 'not authorized to edit this QC item';
  end if;

  update qc_submission_items set result = p_result, notes = coalesce(p_notes, notes), media_asset_id = coalesce(p_media_asset_id, media_asset_id)
  where id = p_item_id
  returning * into v_item;

  return v_item;
end;
$$;

revoke execute on function set_qc_item_result(uuid, text, text, uuid) from public, anon;
grant execute on function set_qc_item_result(uuid, text, text, uuid) to authenticated;

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
  if not (is_org_staff(v_submission.organization_id) or is_assigned_to_work_order(v_submission.work_order_id)) then
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

revoke execute on function submit_qc_for_review(uuid) from public, anon;
grant execute on function submit_qc_for_review(uuid) to authenticated;
