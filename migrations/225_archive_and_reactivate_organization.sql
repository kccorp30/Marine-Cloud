-- =========================================================
-- 225_archive_and_reactivate_organization.sql — Marine Cloud Phase 14
-- =========================================================
-- archive_organization: nunca hard-delete, cancela la suscripción
-- vigente (nunca la borra). reactivate_organization: acción explícita
-- separada — NUNCA reactiva sola una suscripción cancelada ni
-- fabrica un pago.
-- Verificado con datos reales: organización archivada correctamente,
-- reactivación operacional no revive la suscripción sola.
-- =========================================================

create or replace function archive_organization(p_organization_id uuid, p_reason text)
returns organizations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org organizations%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can archive an organization';
  end if;
  if p_reason is null or trim(p_reason) = '' then
    raise exception 'a reason is required to archive an organization';
  end if;

  select * into v_org from organizations where id = p_organization_id for update;
  if v_org.id is null then
    raise exception 'organization not found';
  end if;
  if v_org.status = 'archived' then
    return v_org;
  end if;

  update organizations set status = 'archived', archived_at = now(), archived_by = auth.uid(), archive_reason = p_reason, updated_at = now()
  where id = p_organization_id returning * into v_org;

  update organization_subscriptions set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(), cancellation_reason = 'organization archived', updated_at = now()
  where organization_id = p_organization_id and superseded_at is null and status != 'cancelled';

  perform log_domain_event(p_organization_id, 'ORGANIZATION_ARCHIVED', 'organization', p_organization_id, jsonb_build_object('reason', p_reason));
  perform log_audit_event(p_organization_id, 'organization', p_organization_id, 'organization_archived', jsonb_build_object('status', v_org.status), jsonb_build_object('status', 'archived', 'reason', p_reason));

  return v_org;
end;
$$;

revoke execute on function archive_organization(uuid, text) from public, anon, authenticated;
grant execute on function archive_organization(uuid, text) to authenticated;

create or replace function reactivate_organization(p_organization_id uuid, p_reason text default null)
returns organizations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org organizations%rowtype;
  v_before_status text;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can reactivate an organization';
  end if;

  select * into v_org from organizations where id = p_organization_id for update;
  if v_org.id is null then
    raise exception 'organization not found';
  end if;
  if v_org.status = 'active' then
    return v_org;
  end if;
  v_before_status := v_org.status;

  update organizations set status = 'active', updated_at = now()
  where id = p_organization_id returning * into v_org;

  perform log_domain_event(p_organization_id, 'ORGANIZATION_REACTIVATED', 'organization', p_organization_id, jsonb_build_object('previous_status', v_before_status, 'reason', p_reason));
  perform log_audit_event(p_organization_id, 'organization', p_organization_id, 'organization_reactivated', jsonb_build_object('status', v_before_status), jsonb_build_object('status', 'active', 'reason', p_reason));

  return v_org;
end;
$$;

revoke execute on function reactivate_organization(uuid, text) from public, anon, authenticated;
grant execute on function reactivate_organization(uuid, text) to authenticated;
