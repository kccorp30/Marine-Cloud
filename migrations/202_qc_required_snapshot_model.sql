-- =========================================================
-- 202_qc_required_snapshot_model.sql — Phase 13 final integrity
-- =========================================================
-- GAP REAL AUDITADO: ningún camino de creación de work orders seteaba
-- service_id — resolve_qc_required() usa organization_settings.
-- qc_required_default como fuente real (nunca controlado por el
-- browser), con service_catalog.qc_required como override cuando el
-- work order sí tenga service_id. Snapshoteado al crear, nunca
-- recalculado después.
-- =========================================================

alter table service_catalog add column qc_required boolean not null default false;
alter table organization_settings add column qc_required_default boolean not null default false;

create or replace function resolve_qc_required(p_organization_id uuid, p_service_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select qc_required from service_catalog where id = p_service_id),
    (select qc_required_default from organization_settings where organization_id = p_organization_id),
    false
  );
$$;

revoke execute on function resolve_qc_required(uuid, uuid) from public, anon;
grant execute on function resolve_qc_required(uuid, uuid) to authenticated;

create or replace function convert_estimate_to_work_order(p_estimate_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estimate estimates%rowtype;
  v_work_order_id uuid;
begin
  select * into v_estimate from estimates where id = p_estimate_id for update;
  if v_estimate.id is null then
    raise exception 'estimate not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_estimate.organization_id)) then
    raise exception 'not authorized';
  end if;
  if v_estimate.status != 'approved' then
    raise exception 'estimate must be approved before creating a work order (status: %)', v_estimate.status;
  end if;

  if v_estimate.work_order_id is not null then
    return v_estimate.work_order_id;
  end if;

  insert into work_orders (organization_id, customer_id, vessel_id, title, created_by, qc_required)
  values (v_estimate.organization_id, v_estimate.customer_id, v_estimate.vessel_id,
    coalesce((select title from estimate_versions where id = v_estimate.current_version_id), 'Approved Work'), auth.uid(),
    resolve_qc_required(v_estimate.organization_id, null))
  returning id into v_work_order_id;

  update estimates set work_order_id = v_work_order_id, updated_at = now() where id = p_estimate_id;

  return v_work_order_id;
end;
$$;
