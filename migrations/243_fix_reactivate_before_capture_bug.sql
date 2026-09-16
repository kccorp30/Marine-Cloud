-- =========================================================
-- 243_fix_reactivate_before_capture_bug.sql — Phase 14 true final closure
-- =========================================================
-- BUG REAL en 242: capturaba archived_at/archive_reason para el
-- audit "before" DESPUÉS de que UPDATE...RETURNING * ya había
-- sobrescrito la variable con los valores nuevos (null). Corregido
-- guardando los valores previos ANTES del UPDATE.
-- Verificado con datos reales: campos actuales limpios tras
-- reactivar, evidencia histórica preservada en audit_events.before.
-- =========================================================

create or replace function reactivate_organization(p_organization_id uuid, p_reason text default null)
returns organizations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org organizations%rowtype;
  v_before_status text;
  v_before_archived_at timestamptz;
  v_before_archive_reason text;
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
  v_before_archived_at := v_org.archived_at;
  v_before_archive_reason := v_org.archive_reason;

  update organizations set
    status = 'active', archived_at = null, archived_by = null, archive_reason = null, updated_at = now()
  where id = p_organization_id returning * into v_org;

  perform log_domain_event(p_organization_id, 'ORGANIZATION_REACTIVATED', 'organization', p_organization_id,
    jsonb_build_object('previous_status', v_before_status, 'reason', p_reason));
  perform log_audit_event(p_organization_id, 'organization', p_organization_id, 'organization_reactivated',
    jsonb_build_object('status', v_before_status, 'archived_at', v_before_archived_at, 'archive_reason', v_before_archive_reason),
    jsonb_build_object('status', 'active', 'reason', p_reason));

  return v_org;
end;
$$;
