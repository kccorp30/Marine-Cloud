-- =========================================================
-- 065_estimate_lifecycle_functions.sql — Marine Cloud Phase 6
-- =========================================================
-- Verificado: enviar congela la versión (line item posterior
-- rechazado, UPDATE crudo rechazado por falta de grant), revisar
-- crea V2 y marca V1 superseded, no se puede revisar una estimate ya
-- aprobada/cancelada.
-- =========================================================

create or replace function send_estimate(p_estimate_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estimate estimates%rowtype;
  v_version estimate_versions%rowtype;
  v_line_count int;
begin
  select * into v_estimate from estimates where id = p_estimate_id for update;
  if v_estimate.id is null then
    raise exception 'estimate not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_estimate.organization_id)) then
    raise exception 'not authorized';
  end if;

  select * into v_version from estimate_versions where id = v_estimate.current_version_id for update;
  if v_version.status != 'draft' then
    raise exception 'current version is not a draft (status: %)', v_version.status;
  end if;

  select count(*) into v_line_count from estimate_line_items where estimate_version_id = v_version.id;
  if v_line_count = 0 then
    raise exception 'cannot send an estimate with no line items';
  end if;

  update estimate_versions set status = 'sent', sent_at = now() where id = v_version.id;
  update estimates set status = 'sent', updated_at = now() where id = p_estimate_id;

  perform log_domain_event(v_estimate.organization_id, 'ESTIMATE_SENT', 'estimate', p_estimate_id,
    jsonb_build_object('estimate_version_id', v_version.id, 'total', v_version.total));
  perform log_audit_event(v_estimate.organization_id, 'estimate', p_estimate_id, 'estimate_sent',
    jsonb_build_object('version', v_version.version_number), jsonb_build_object('total', v_version.total));
end;
$$;

revoke execute on function send_estimate(uuid) from public, anon;
grant execute on function send_estimate(uuid) to authenticated;

create or replace function mark_estimate_viewed(p_estimate_version_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version estimate_versions%rowtype;
  v_estimate estimates%rowtype;
begin
  select * into v_version from estimate_versions where id = p_estimate_version_id;
  if v_version.id is null then
    raise exception 'estimate version not found';
  end if;
  select * into v_estimate from estimates where id = v_version.estimate_id;
  if not is_own_customer_record(v_estimate.customer_id) then
    raise exception 'not authorized';
  end if;

  if v_version.status = 'sent' then
    update estimate_versions set status = 'viewed' where id = p_estimate_version_id;
    update estimates set status = 'viewed' where id = v_estimate.id and status = 'sent';
    perform log_domain_event(v_estimate.organization_id, 'ESTIMATE_VIEWED', 'estimate', v_estimate.id,
      jsonb_build_object('estimate_version_id', p_estimate_version_id));
  end if;
end;
$$;

revoke execute on function mark_estimate_viewed(uuid) from public, anon;
grant execute on function mark_estimate_viewed(uuid) to authenticated;

create or replace function revise_estimate(p_estimate_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estimate estimates%rowtype;
  v_old_version estimate_versions%rowtype;
  v_new_version_id uuid;
  v_next_number int;
begin
  select * into v_estimate from estimates where id = p_estimate_id for update;
  if v_estimate.id is null then
    raise exception 'estimate not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_estimate.organization_id)) then
    raise exception 'not authorized';
  end if;
  if v_estimate.status in ('approved', 'cancelled') then
    raise exception 'cannot revise an estimate that is % — original approved terms must stay unchanged', v_estimate.status;
  end if;

  select * into v_old_version from estimate_versions where id = v_estimate.current_version_id for update;
  if v_old_version.status = 'draft' then
    raise exception 'current version is already a draft — edit it directly instead of revising';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_number from estimate_versions where estimate_id = p_estimate_id;

  update estimate_versions set status = 'superseded', superseded_at = now() where id = v_old_version.id;

  insert into estimate_versions (organization_id, estimate_id, version_number, status, title, customer_message, tax, currency, valid_until, created_by)
  values (v_estimate.organization_id, p_estimate_id, v_next_number, 'draft', v_old_version.title, v_old_version.customer_message, v_old_version.tax, v_old_version.currency, v_old_version.valid_until, auth.uid())
  returning id into v_new_version_id;

  insert into estimate_line_items (organization_id, estimate_version_id, service_catalog_id, line_type, description, quantity, unit_price, sort_order, customer_visible)
  select organization_id, v_new_version_id, service_catalog_id, line_type, description, quantity, unit_price, sort_order, customer_visible
  from estimate_line_items where estimate_version_id = v_old_version.id;

  update estimates set current_version_id = v_new_version_id, status = 'draft', updated_at = now() where id = p_estimate_id;

  perform log_domain_event(v_estimate.organization_id, 'ESTIMATE_SUPERSEDED', 'estimate', p_estimate_id,
    jsonb_build_object('superseded_version_id', v_old_version.id, 'new_version_id', v_new_version_id));
  perform log_domain_event(v_estimate.organization_id, 'ESTIMATE_VERSION_CREATED', 'estimate', p_estimate_id,
    jsonb_build_object('estimate_version_id', v_new_version_id, 'version_number', v_next_number));

  return v_new_version_id;
end;
$$;

revoke execute on function revise_estimate(uuid) from public, anon;
grant execute on function revise_estimate(uuid) to authenticated;

create or replace function cancel_estimate(p_estimate_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estimate estimates%rowtype;
begin
  select * into v_estimate from estimates where id = p_estimate_id for update;
  if v_estimate.id is null then
    raise exception 'estimate not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_estimate.organization_id)) then
    raise exception 'not authorized';
  end if;
  if v_estimate.status in ('approved', 'cancelled') then
    raise exception 'cannot cancel an estimate that is %', v_estimate.status;
  end if;

  update estimates set status = 'cancelled', updated_at = now() where id = p_estimate_id;
  perform log_domain_event(v_estimate.organization_id, 'ESTIMATE_CANCELLED', 'estimate', p_estimate_id, '{}'::jsonb);
  perform log_audit_event(v_estimate.organization_id, 'estimate', p_estimate_id, 'estimate_cancelled', null, null);
end;
$$;

revoke execute on function cancel_estimate(uuid) from public, anon;
grant execute on function cancel_estimate(uuid) to authenticated;
