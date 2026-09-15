-- =========================================================
-- 117_retry_failed_message_function.sql — Phase 8 hardening
-- =========================================================
-- BUG REAL encontrado probando el reintento: la capa de Next.js
-- intentaba un UPDATE directo sobre messages — tabla bloqueada a
-- solo SELECT para authenticated. Se agrega la función real que
-- faltaba. Verificado con datos reales: mueve failed -> queued
-- limpiando failure_reason; rechaza reintentar un mensaje que no
-- está failed.
-- =========================================================

create or replace function retry_failed_message(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message messages%rowtype;
begin
  select * into v_message from messages where id = p_message_id for update;
  if v_message.id is null then
    raise exception 'message not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_message.organization_id)) then
    raise exception 'not authorized';
  end if;
  if v_message.status != 'failed' then
    raise exception 'only a failed message can be retried (current status: %)', v_message.status;
  end if;

  update messages set status = 'queued', failed_at = null, failure_reason = null where id = p_message_id;

  perform log_audit_event(v_message.organization_id, 'message', p_message_id, 'message_retry', null, null);
end;
$$;

revoke execute on function retry_failed_message(uuid) from public, anon;
grant execute on function retry_failed_message(uuid) to authenticated;
