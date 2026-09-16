-- =========================================================
-- 135_durable_notification_failure_retry.sql — Phase 9 final fix
-- =========================================================
-- BUG REAL: generate_notifications_from_domain_event() solo hacía
-- RAISE WARNING ante un fallo — la notificación se perdía para
-- siempre, sin quedar en ningún lado consultable ni reintentable.
--
-- Se extrae la lógica core a process_domain_event_notifications()
-- (reusable por el trigger Y por el reintento). El trigger sigue sin
-- revertir la transacción de negocio, pero ahora persiste el fallo
-- en notification_processing_failures, reintentable solo por el
-- actor de plataforma de confianza (is_platform_trusted_actor(), ya
-- usado en Phase 8).
--
-- Verificado con datos reales: fallo forzado -> domain_event sigue
-- insertado (transacción de negocio sobrevive), fallo persistido
-- durablemente (no solo WARNING), authenticated normal rechazado al
-- intentar reintentar, service_role sí puede, reintentar algo ya
-- 'processed' rechazado, reprocesar un evento real no duplica
-- notificaciones.
-- =========================================================

create table notification_processing_failures (
  id uuid primary key default gen_random_uuid(),
  source_domain_event_id uuid not null references domain_events(id),
  status text not null default 'pending' check (status in ('pending', 'processed', 'permanently_failed')),
  attempt_count int not null default 1,
  last_error text,
  next_retry_at timestamptz,
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint uq_notification_failure_event unique (source_domain_event_id)
);

create index idx_notification_failures_pending on notification_processing_failures(status, next_retry_at) where status = 'pending';

alter table notification_processing_failures enable row level security;

create policy "read_notification_failures" on notification_processing_failures for select
using (is_kcc_admin());

revoke all on notification_processing_failures from anon, authenticated;
grant select on notification_processing_failures to authenticated;

create or replace function process_domain_event_notifications(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event domain_events%rowtype;
  v_rule notification_rules%rowtype;
  v_recipient uuid;
  v_title text;
  v_body text;
begin
  select * into v_event from domain_events where id = p_event_id;
  if v_event.id is null then
    raise exception 'domain_event % not found', p_event_id;
  end if;

  for v_rule in
    select * from notification_rules
    where event_type = v_event.event_type
      and is_active = true
      and (organization_id is null or organization_id = v_event.organization_id)
      and (payload_filter is null or v_event.payload @> payload_filter)
  loop
    v_title := render_notification_text(v_rule.title_template, v_event.payload, v_event.work_order_id);
    v_body := case when v_rule.body_template is not null then render_notification_text(v_rule.body_template, v_event.payload, v_event.work_order_id) else null end;

    for v_recipient in
      select * from resolve_notification_recipients(v_rule.recipient_strategy, v_event.organization_id, v_event.work_order_id, v_event.entity_type, v_event.entity_id)
    loop
      insert into notifications (
        organization_id, recipient_user_id, event_type, severity, title, body,
        related_entity_type, related_entity_id, acknowledgement_required,
        source_domain_event_id, source_rule_id
      )
      values (
        v_event.organization_id, v_recipient, v_event.event_type, v_rule.severity, v_title, v_body,
        v_event.entity_type, v_event.entity_id, v_rule.acknowledgement_required,
        v_event.id, v_rule.id
      )
      on conflict do nothing;
    end loop;
  end loop;
end;
$$;

revoke execute on function process_domain_event_notifications(uuid) from public, anon, authenticated;

create or replace function generate_notifications_from_domain_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    perform process_domain_event_notifications(NEW.id);
  exception when others then
    insert into notification_processing_failures (source_domain_event_id, status, attempt_count, last_error, next_retry_at)
    values (NEW.id, 'pending', 1, sqlerrm, now() + interval '5 minutes')
    on conflict (source_domain_event_id) do update set
      attempt_count = notification_processing_failures.attempt_count + 1,
      last_error = excluded.last_error,
      next_retry_at = now() + interval '5 minutes',
      updated_at = now();
    raise warning 'notification generation failed for domain_event %: %', NEW.id, sqlerrm;
  end;

  return NEW;
end;
$$;

create or replace function retry_notification_processing(p_failure_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_failure notification_processing_failures%rowtype;
begin
  if not is_platform_trusted_actor() then
    raise exception 'only the trusted platform actor can retry notification processing';
  end if;

  select * into v_failure from notification_processing_failures where id = p_failure_id for update;
  if v_failure.id is null then
    raise exception 'failure record not found';
  end if;
  if v_failure.status != 'pending' then
    raise exception 'only a pending failure can be retried (current status: %)', v_failure.status;
  end if;

  begin
    perform process_domain_event_notifications(v_failure.source_domain_event_id);
    update notification_processing_failures set status = 'processed', processed_at = now(), updated_at = now() where id = p_failure_id;
  exception when others then
    update notification_processing_failures set
      attempt_count = attempt_count + 1,
      last_error = sqlerrm,
      next_retry_at = now() + (interval '5 minutes' * (attempt_count + 1)),
      status = case when attempt_count + 1 >= 5 then 'permanently_failed' else 'pending' end,
      updated_at = now()
    where id = p_failure_id;
    raise;
  end;
end;
$$;

revoke execute on function retry_notification_processing(uuid) from public, anon;
grant execute on function retry_notification_processing(uuid) to authenticated;
