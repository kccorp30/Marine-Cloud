-- =========================================================
-- 016_fix_event_functions_authorization.sql — Marine Cloud Phase 0
-- =========================================================
-- Bug real (encontrado vía security advisor): log_domain_event() y
-- log_audit_event() son SECURITY DEFINER y estaban otorgadas a
-- `authenticated` (necesario para que las políticas RLS las invoquen),
-- pero PostgREST también las expone como endpoints RPC directos —
-- y las funciones NO verificaban que quien llama tenga permiso real
-- sobre la organización que pasa como parámetro. Cualquier usuario
-- logueado podía insertar eventos falsos para OTRA organización.

create or replace function log_domain_event(
  p_organization_id uuid,
  p_event_type text,
  p_entity_type text,
  p_entity_id uuid,
  p_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not (is_org_member(p_organization_id) or is_kcc_admin()) then
    raise exception 'not authorized to log events for this organization';
  end if;

  insert into domain_events (organization_id, event_type, entity_type, entity_id, payload, actor_profile_id)
  values (p_organization_id, p_event_type, p_entity_type, p_entity_id, p_payload, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function log_audit_event(
  p_organization_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_action text,
  p_before jsonb default null,
  p_after jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  -- p_organization_id puede ser null (acciones cross-tenant de KCC) —
  -- en ese caso, solo kcc_admin puede registrar. Si tiene organización,
  -- debe ser staff de ESA organización o kcc_admin.
  if p_organization_id is null then
    if not is_kcc_admin() then
      raise exception 'not authorized to log cross-tenant audit events';
    end if;
  else
    if not (is_org_staff(p_organization_id) or is_kcc_admin()) then
      raise exception 'not authorized to log audit events for this organization';
    end if;
  end if;

  insert into audit_events (organization_id, actor_profile_id, entity_type, entity_id, action, before, after)
  values (p_organization_id, auth.uid(), p_entity_type, p_entity_id, p_action, p_before, p_after)
  returning id into v_id;
  return v_id;
end;
$$;

-- El trigger genérico sigue funcionando: cuando se dispara por un
-- UPDATE ya autorizado por RLS (el usuario ya pudo hacer el UPDATE
-- porque pasó la policy de la tabla), is_org_staff()/is_kcc_admin()
-- sobre esa misma organización naturalmente será true — no rompe
-- el flujo normal, solo bloquea la llamada directa maliciosa vía RPC.

-- is_org_member / is_org_staff: revocar explícitamente de anon
-- (el revoke de PUBLIC no alcanzó a anon — ver hallazgo del advisor;
-- Supabase otorga EXECUTE directo a anon/authenticated vía default
-- privileges al crear la función, independiente de REVOKE ... FROM PUBLIC).
revoke execute on function is_org_member(uuid) from anon;
revoke execute on function is_org_staff(uuid) from anon;
revoke execute on function log_domain_event(uuid, text, text, uuid, jsonb) from anon;
revoke execute on function log_audit_event(uuid, text, uuid, text, jsonb, jsonb) from anon;
revoke execute on function is_kcc_admin() from anon;
