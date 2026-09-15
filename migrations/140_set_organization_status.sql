-- =========================================================
-- 140_set_organization_status.sql — Marine Cloud Phase 10
-- =========================================================
-- Solo kcc_admin. Nunca borra datos. Emite el evento específico
-- según la transición real. Verificado con datos reales: no
-- autorizado rechazado, kcc_admin suspende/reactiva, datos
-- históricos preservados.
-- =========================================================

create or replace function set_organization_status(p_organization_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org organizations%rowtype;
  v_event_type text;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can change organization status';
  end if;
  if p_status not in ('active', 'inactive', 'suspended') then
    raise exception 'invalid status: %', p_status;
  end if;

  select * into v_org from organizations where id = p_organization_id for update;
  if v_org.id is null then
    raise exception 'organization not found';
  end if;
  if v_org.status = p_status then
    raise exception 'organization is already %', p_status;
  end if;

  v_event_type := case
    when p_status = 'suspended' then 'ORGANIZATION_SUSPENDED'
    when p_status = 'active' and v_org.status = 'suspended' then 'ORGANIZATION_REACTIVATED'
    when p_status = 'active' then 'ORGANIZATION_ACTIVATED'
    else 'ORGANIZATION_STATUS_CHANGED'
  end;

  update organizations set status = p_status, updated_at = now() where id = p_organization_id;

  perform log_domain_event(p_organization_id, v_event_type, 'organization', p_organization_id,
    jsonb_build_object('from_status', v_org.status, 'to_status', p_status));
  perform log_audit_event(p_organization_id, 'organization', p_organization_id, 'organization_status_changed',
    jsonb_build_object('status', v_org.status), jsonb_build_object('status', p_status));
end;
$$;

revoke execute on function set_organization_status(uuid, text) from public, anon;
grant execute on function set_organization_status(uuid, text) to authenticated;
