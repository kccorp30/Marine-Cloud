-- =========================================================
-- 122_allow_platform_trusted_actor_to_log_events.sql — Phase 8 final fix
-- =========================================================
-- BUG REAL Y CRÍTICO encontrado verificando el camino real de
-- service_role (no simulado con kcc_admin): log_domain_event()/
-- log_audit_event() solo aceptaban is_org_member()/is_org_staff()/
-- is_kcc_admin() — todos dependientes de auth.uid(), que es NULL
-- bajo una sesión service_role real. Esto significaba que la ruta
-- REAL de producción (webhook de Resend + confirmación real de envío
-- desde Next.js, ambas vía el cliente de service role) habría
-- fallado por completo al intentar loguear su propio evento — y como
-- el fallo ocurre sin manejo de excepción dentro de
-- record_provider_send_result()/process_email_webhook_event(), la
-- transacción entera se revertía, incluyendo el UPDATE de status. En
-- los hechos, la Phase 8 real habría estado completamente rota en
-- producción pese a que las pruebas con kcc_admin (que sí pasa
-- is_kcc_admin()) mostraban PASS — un actor distinto enmascaraba el
-- bug real del actor que de verdad se usa en producción.
--
-- Fix: ambas funciones ahora también aceptan is_platform_trusted_
-- actor(). Verificado con una sesión service_role real (rol de
-- Postgres + JWT claim role=service_role), no simulada con kcc_admin:
-- el ciclo completo queued -> sent -> delivered funciona de punta a
-- punta.
-- =========================================================

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
  if not (is_org_member(p_organization_id) or is_kcc_admin() or is_platform_trusted_actor()) then
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
begin
  if p_organization_id is null then
    if not (is_kcc_admin() or is_platform_trusted_actor()) then
      raise exception 'not authorized to log cross-tenant audit events';
    end if;
  else
    if not (is_org_staff(p_organization_id) or is_kcc_admin() or is_platform_trusted_actor()) then
      raise exception 'not authorized to log audit events for this organization';
    end if;
  end if;

  return log_audit_event_internal(p_organization_id, p_entity_type, p_entity_id, p_action, p_before, p_after);
end;
$$;
