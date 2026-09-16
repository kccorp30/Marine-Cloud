-- =========================================================
-- 103_conversation_and_message_functions.sql — Marine Cloud Phase 8
-- =========================================================
-- La traducción/reescritura ocurre en la capa de Next.js (llamando a
-- la API de Anthropic con la clave de plataforma, nunca desde SQL) —
-- estas funciones solo PERSISTEN el resultado ya generado, con
-- autorización y auditoría reales. body_original nunca se sobreescribe
-- al traducir — verificado con datos reales.
-- =========================================================

create or replace function get_or_create_conversation(
  p_organization_id uuid,
  p_customer_id uuid,
  p_vessel_id uuid default null,
  p_work_order_id uuid default null,
  p_service_request_id uuid default null,
  p_subject text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conversation_id uuid;
begin
  if not (is_kcc_admin() or is_org_staff(p_organization_id)) then
    raise exception 'not authorized';
  end if;
  if not exists (select 1 from customers where id = p_customer_id and organization_id = p_organization_id) then
    raise exception 'customer does not belong to this organization';
  end if;

  select id into v_conversation_id from conversations
  where organization_id = p_organization_id and customer_id = p_customer_id
    and status = 'open'
    and coalesce(work_order_id::text, '') = coalesce(p_work_order_id::text, '')
  limit 1;

  if v_conversation_id is not null then
    return v_conversation_id;
  end if;

  insert into conversations (organization_id, customer_id, vessel_id, work_order_id, service_request_id, subject, created_by)
  values (p_organization_id, p_customer_id, p_vessel_id, p_work_order_id, p_service_request_id, p_subject, auth.uid())
  returning id into v_conversation_id;

  return v_conversation_id;
end;
$$;

revoke execute on function get_or_create_conversation(uuid, uuid, uuid, uuid, uuid, text) from public, anon;
grant execute on function get_or_create_conversation(uuid, uuid, uuid, uuid, uuid, text) to authenticated;

create or replace function send_message(
  p_conversation_id uuid,
  p_channel text,
  p_body_original text,
  p_body_rendered text default null,
  p_language_original text default null,
  p_language_rendered text default null
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

  insert into messages (organization_id, conversation_id, sender_type, sender_profile_id, direction, channel,
    body_original, body_rendered, language_original, language_rendered, status, sent_at)
  values (v_conversation.organization_id, p_conversation_id, 'staff', auth.uid(), 'outbound', p_channel,
    p_body_original, p_body_rendered, p_language_original, p_language_rendered, 'sent', now())
  returning id into v_message_id;

  update conversations set last_message_at = now(), updated_at = now(), status = 'open' where id = p_conversation_id;

  perform log_domain_event(v_conversation.organization_id, 'MESSAGE_SENT', 'message', v_message_id,
    jsonb_build_object('conversation_id', p_conversation_id, 'channel', p_channel));
  perform log_audit_event(v_conversation.organization_id, 'message', v_message_id, 'message_sent',
    null, jsonb_build_object('channel', p_channel, 'conversation_id', p_conversation_id));

  return v_message_id;
end;
$$;

revoke execute on function send_message(uuid, text, text, text, text, text) from public, anon;
grant execute on function send_message(uuid, text, text, text, text, text) to authenticated;

create or replace function mark_message_delivered(p_message_id uuid, p_provider_message_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  select organization_id into v_org_id from messages where id = p_message_id;
  if v_org_id is null then
    raise exception 'message not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_org_id)) then
    raise exception 'not authorized';
  end if;

  update messages set status = 'delivered', delivered_at = now(), provider_message_id = coalesce(p_provider_message_id, provider_message_id)
  where id = p_message_id;
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
  select organization_id into v_org_id from messages where id = p_message_id;
  if v_org_id is null then
    raise exception 'message not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_org_id)) then
    raise exception 'not authorized';
  end if;

  update messages set status = 'failed', failed_at = now(), failure_reason = p_reason where id = p_message_id;
end;
$$;

revoke execute on function mark_message_failed(uuid, text) from public, anon;
grant execute on function mark_message_failed(uuid, text) to authenticated;

create or replace function create_message_template(
  p_organization_id uuid,
  p_name text,
  p_category text,
  p_language text,
  p_subject text,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not (is_kcc_admin() or is_org_staff(p_organization_id)) then
    raise exception 'not authorized';
  end if;

  insert into message_templates (organization_id, name, category, language, subject, body, created_by)
  values (p_organization_id, p_name, p_category, p_language, p_subject, p_body, auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function create_message_template(uuid, text, text, text, text, text) from public, anon;
grant execute on function create_message_template(uuid, text, text, text, text, text) to authenticated;
