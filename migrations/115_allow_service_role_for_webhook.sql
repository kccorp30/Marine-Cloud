-- =========================================================
-- 115_allow_service_role_for_webhook.sql — Phase 8 hardening
-- =========================================================
-- BUG REAL encontrado armando el webhook: con la service_role key,
-- auth.uid() es NULL — is_kcc_admin() SIEMPRE habría fallado, dejando
-- el webhook real inutilizable. Se agrega is_platform_trusted_actor()
-- que acepta kcc_admin autenticado normal O el JWT de service_role.
-- =========================================================

create or replace function is_platform_trusted_actor()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select is_kcc_admin() or coalesce(current_setting('request.jwt.claims', true)::json->>'role', '') = 'service_role';
$$;

revoke execute on function is_platform_trusted_actor() from public, anon;
grant execute on function is_platform_trusted_actor() to authenticated;

create or replace function mark_message_delivered(p_message_id uuid, p_provider_message_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  if not is_platform_trusted_actor() then
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

create or replace function mark_message_failed(p_message_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  if not is_platform_trusted_actor() then
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
  if not is_platform_trusted_actor() then
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

drop policy if exists "read_webhook_events" on provider_webhook_events;
create policy "read_webhook_events" on provider_webhook_events for select using (is_kcc_admin());
