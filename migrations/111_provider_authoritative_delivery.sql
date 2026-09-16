-- =========================================================
-- 111_provider_authoritative_delivery.sql — Phase 8 hardening
-- =========================================================
-- BUG REAL: mark_message_delivered()/mark_message_failed() eran
-- callables por cualquier staff. Diseño real: queued (registro
-- existe, proveedor aún no llamado) -> sent (proveedor aceptó — lo
-- registra el mismo staff que envió, vía record_provider_send_result,
-- continuación síncrona de su propia acción) -> delivered/bounced/
-- complained (solo el proveedor real lo sabe — solo vía webhook,
-- kcc_admin/service_role). send_message() reserva la idempotencia
-- ANTES de que Next.js llame al proveedor real.
-- Verificado con datos reales: staff no puede forjar delivered,
-- webhook idempotente (mismo evento dos veces no duplica).
-- =========================================================

alter table messages drop constraint messages_status_check;
alter table messages add constraint messages_status_check check (status in ('draft', 'queued', 'sent', 'delivered', 'failed', 'bounced', 'complained'));

create table provider_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'resend',
  provider_event_id text not null,
  message_id uuid references messages(id),
  event_type text not null,
  processed_at timestamptz not null default now(),
  raw_payload jsonb,

  constraint uq_webhook_provider_event unique (provider, provider_event_id)
);

alter table provider_webhook_events enable row level security;
create policy "read_webhook_events" on provider_webhook_events for select using (is_kcc_admin());
revoke all on provider_webhook_events from anon, authenticated;
grant select on provider_webhook_events to authenticated;

create or replace function send_message(
  p_conversation_id uuid,
  p_channel text,
  p_body_original text,
  p_subject text default null,
  p_body_rendered text default null,
  p_language_original text default null,
  p_language_rendered text default null,
  p_customer_visible boolean default true,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conversation conversations%rowtype;
  v_message_id uuid;
begin
  select * into v_conversation from conversations where id = p_conversation_id for update;
  if v_conversation.id is null then
    raise exception 'conversation not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_conversation.organization_id)) then
    raise exception 'not authorized to send messages';
  end if;
  if v_conversation.status = 'archived' then
    raise exception 'cannot send a message on an archived conversation';
  end if;
  if p_body_original is null or length(trim(p_body_original)) = 0 then
    raise exception 'message body cannot be empty';
  end if;
  if p_channel = 'internal' and p_customer_visible then
    raise exception 'internal messages can never be customer_visible';
  end if;

  if p_idempotency_key is not null then
    select id into v_message_id from messages where conversation_id = p_conversation_id and idempotency_key = p_idempotency_key;
    if v_message_id is not null then
      return v_message_id;
    end if;
  end if;

  insert into messages (organization_id, conversation_id, sender_type, sender_profile_id, direction, channel,
    body_original, subject, body_rendered, language_original, language_rendered, status, customer_visible, idempotency_key)
  values (v_conversation.organization_id, p_conversation_id, 'staff', auth.uid(), 'outbound', p_channel,
    p_body_original, p_subject, p_body_rendered, p_language_original, p_language_rendered,
    case when p_channel = 'internal' then 'sent' else 'queued' end,
    p_customer_visible, p_idempotency_key)
  returning id into v_message_id;

  update conversations set last_message_at = now(), updated_at = now(), status = 'open' where id = p_conversation_id;

  if p_channel = 'internal' then
    perform log_domain_event(v_conversation.organization_id, 'MESSAGE_SENT', 'message', v_message_id,
      jsonb_build_object('conversation_id', p_conversation_id, 'channel', p_channel));
  else
    perform log_domain_event(v_conversation.organization_id, 'MESSAGE_DRAFT_CREATED', 'message', v_message_id,
      jsonb_build_object('conversation_id', p_conversation_id, 'channel', p_channel));
  end if;
  perform log_audit_event(v_conversation.organization_id, 'message', v_message_id, 'message_queued',
    null, jsonb_build_object('channel', p_channel, 'conversation_id', p_conversation_id));

  return v_message_id;
end;
$$;

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
  if not (is_kcc_admin() or is_org_staff(v_message.organization_id)) then
    raise exception 'not authorized';
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

revoke execute on function record_provider_send_result(uuid, boolean, text, text) from public, anon;
grant execute on function record_provider_send_result(uuid, boolean, text, text) to authenticated;

create or replace function mark_message_delivered(p_message_id uuid, p_provider_message_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  if not is_kcc_admin() then
    raise exception 'only the platform-trusted webhook path can confirm real delivery';
  end if;
  select organization_id into v_org_id from messages where id = p_message_id;
  if v_org_id is null then
    raise exception 'message not found';
  end if;

  update messages set status = 'delivered', delivered_at = now(), provider_message_id = coalesce(p_provider_message_id, provider_message_id)
  where id = p_message_id;

  perform log_domain_event(v_org_id, 'EMAIL_DELIVERED', 'message', p_message_id, '{}'::jsonb);
end;
$$;

revoke execute on function mark_message_delivered(uuid, text) from public, anon;
grant execute on function mark_message_delivered(uuid, text) to authenticated;

create or replace function mark_message_failed(p_message_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  if not is_kcc_admin() then
    raise exception 'only the platform-trusted webhook path can report async delivery failure';
  end if;
  select organization_id into v_org_id from messages where id = p_message_id;
  if v_org_id is null then
    raise exception 'message not found';
  end if;

  update messages set status = 'failed', failed_at = now(), failure_reason = p_reason where id = p_message_id;
  perform log_domain_event(v_org_id, 'MESSAGE_FAILED', 'message', p_message_id, jsonb_build_object('reason', p_reason));
end;
$$;

revoke execute on function mark_message_failed(uuid, text) from public, anon;
grant execute on function mark_message_failed(uuid, text) to authenticated;

create or replace function process_email_webhook_event(
  p_provider_event_id text,
  p_provider_message_id text,
  p_event_type text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message_id uuid;
  v_org_id uuid;
begin
  if not is_kcc_admin() then
    raise exception 'only the platform-trusted webhook path can process delivery events';
  end if;

  if exists (select 1 from provider_webhook_events where provider = 'resend' and provider_event_id = p_provider_event_id) then
    return;
  end if;

  select id, organization_id into v_message_id, v_org_id from messages where provider_message_id = p_provider_message_id;

  insert into provider_webhook_events (provider, provider_event_id, message_id, event_type)
  values ('resend', p_provider_event_id, v_message_id, p_event_type);

  if v_message_id is null then
    return;
  end if;

  if p_event_type = 'delivered' then
    update messages set status = 'delivered', delivered_at = now() where id = v_message_id and status != 'delivered';
    perform log_domain_event(v_org_id, 'EMAIL_DELIVERED', 'message', v_message_id, '{}'::jsonb);
  elsif p_event_type = 'bounced' then
    update messages set status = 'bounced', failed_at = now(), failure_reason = 'bounced' where id = v_message_id;
    perform log_domain_event(v_org_id, 'EMAIL_BOUNCED', 'message', v_message_id, '{}'::jsonb);
  elsif p_event_type = 'complained' then
    update messages set status = 'complained' where id = v_message_id;
  end if;
end;
$$;

revoke execute on function process_email_webhook_event(text, text, text) from public, anon;
grant execute on function process_email_webhook_event(text, text, text) to authenticated;
