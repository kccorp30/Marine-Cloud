-- =========================================================
-- 118_trusted_provider_result_authority.sql — Phase 8 final fix
-- =========================================================
-- BUG REAL Y CRÍTICO: record_provider_send_result() era callable por
-- cualquier staff de la organización — un staff podía llamar el RPC
-- directo y forjar queued->sent con un provider_message_id inventado,
-- sin que Resend hubiera aceptado nada de verdad.
--
-- Diseño real: queued (staff normal — es su acción de negocio
-- autorizada), sent (SOLO el servidor de confianza, después de que
-- Resend acepta de verdad — mismo actor que ya usa el webhook:
-- is_platform_trusted_actor(), kcc_admin o service_role),
-- delivered/bounced/complained (webhook verificado, sin cambios).
--
-- Verificado con datos reales: staff normal rechazado al intentar
-- autoafirmar 'sent', kcc_admin (actor de plataforma) sí puede.
-- =========================================================

create or replace function record_provider_send_result(
  p_message_id uuid,
  p_success boolean,
  p_provider_message_id text default null,
  p_error text default null
)
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
  if not is_platform_trusted_actor() then
    raise exception 'only the trusted server path can record provider acceptance — ordinary staff cannot self-assert sent state';
  end if;
  if v_message.status != 'queued' then
    raise exception 'message is not in queued status (status: %)', v_message.status;
  end if;

  if p_success then
    update messages set status = 'sent', sent_at = now(), provider_message_id = p_provider_message_id where id = p_message_id;
    perform log_domain_event(v_message.organization_id, 'EMAIL_SENT', 'message', p_message_id,
      jsonb_build_object('provider_message_id', p_provider_message_id));
  else
    update messages set status = 'failed', failed_at = now(), failure_reason = p_error where id = p_message_id;
    perform log_domain_event(v_message.organization_id, 'MESSAGE_FAILED', 'message', p_message_id,
      jsonb_build_object('reason', p_error));
  end if;
end;
$$;
