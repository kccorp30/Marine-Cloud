-- =========================================================
-- 125_notification_engine.sql — Marine Cloud Phase 9
-- =========================================================
-- Elección de arquitectura: TRIGGER de base de datos sobre
-- domain_events (AFTER INSERT), consistente con el patrón ya
-- establecido (trg_domain_events_update_last_activity,
-- trg_resolve_domain_event_wo ya viven exactamente ahí). Nunca
-- polling desde el browser. Fallos de notificación NUNCA corrompen
-- la transacción de negocio original.
--
-- Verificado con datos reales: asignación de técnico dispara
-- notificación real al customer con {{vessel_name}} resuelto,
-- WORK_ORDER_STATUS_CHANGED->awaiting_approval genera
-- action_required, evento no relacionado no genera nada,
-- reprocesar el mismo evento no duplica.
-- =========================================================

create or replace function render_notification_text(
  p_template text,
  p_payload jsonb,
  p_work_order_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_text text := p_template;
  v_vessel_name text;
  v_wo_title text;
begin
  if p_work_order_id is not null then
    select v.name, wo.title into v_vessel_name, v_wo_title
    from work_orders wo left join vessels v on v.id = wo.vessel_id
    where wo.id = p_work_order_id;
  end if;

  v_text := replace(v_text, '{{vessel_name}}', coalesce(v_vessel_name, 'your vessel'));
  v_text := replace(v_text, '{{work_order_title}}', coalesce(v_wo_title, ''));
  v_text := replace(v_text, '{{to_status}}', coalesce(p_payload->>'to_status', ''));
  v_text := replace(v_text, '{{from_status}}', coalesce(p_payload->>'from_status', ''));
  v_text := replace(v_text, '{{reason}}', coalesce(p_payload->>'reason', p_payload->>'category', ''));

  return v_text;
end;
$$;

create or replace function resolve_notification_recipients(
  p_recipient_strategy text,
  p_organization_id uuid,
  p_work_order_id uuid,
  p_entity_type text,
  p_entity_id uuid
)
returns setof uuid
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if p_recipient_strategy = 'org_staff' then
    return query
      select profile_id from organization_memberships
      where organization_id = p_organization_id and status = 'active'
        and role in ('company_owner', 'company_admin', 'manager');

  elsif p_recipient_strategy = 'assigned_technician' then
    return query
      select technician_profile_id from assignments
      where work_order_id = p_work_order_id and status = 'active';

  elsif p_recipient_strategy = 'customer' then
    return query
      select c.profile_id from work_orders wo
      join customers c on c.id = wo.customer_id
      where wo.id = p_work_order_id and c.profile_id is not null;

  elsif p_recipient_strategy = 'kcc_admin' then
    return query
      select distinct profile_id from organization_memberships
      where role = 'kcc_admin' and status = 'active';

  elsif p_recipient_strategy = 'requesting_technician' then
    if p_entity_type = 'kcc_assistance_request' then
      return query
        select requesting_technician_id from kcc_assistance_requests where id = p_entity_id;
    end if;
    return;
  end if;

  return;
end;
$$;

revoke execute on function render_notification_text(text, jsonb, uuid) from public, anon;
revoke execute on function resolve_notification_recipients(text, uuid, uuid, text, uuid) from public, anon;

create or replace function generate_notifications_from_domain_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rule notification_rules%rowtype;
  v_recipient uuid;
  v_title text;
  v_body text;
begin
  begin
    for v_rule in
      select * from notification_rules
      where event_type = NEW.event_type
        and is_active = true
        and (organization_id is null or organization_id = NEW.organization_id)
        and (payload_filter is null or NEW.payload @> payload_filter)
    loop
      v_title := render_notification_text(v_rule.title_template, NEW.payload, NEW.work_order_id);
      v_body := case when v_rule.body_template is not null then render_notification_text(v_rule.body_template, NEW.payload, NEW.work_order_id) else null end;

      for v_recipient in
        select * from resolve_notification_recipients(v_rule.recipient_strategy, NEW.organization_id, NEW.work_order_id, NEW.entity_type, NEW.entity_id)
      loop
        insert into notifications (
          organization_id, recipient_user_id, event_type, severity, title, body,
          related_entity_type, related_entity_id, acknowledgement_required,
          source_domain_event_id, source_rule_id
        )
        values (
          NEW.organization_id, v_recipient, NEW.event_type, v_rule.severity, v_title, v_body,
          NEW.entity_type, NEW.entity_id, v_rule.acknowledgement_required,
          NEW.id, v_rule.id
        )
        on conflict do nothing;
      end loop;
    end loop;
  exception when others then
    raise warning 'notification generation failed for domain_event %: %', NEW.id, sqlerrm;
  end;

  return NEW;
end;
$$;

create trigger trg_generate_notifications_from_domain_event
  after insert on domain_events
  for each row execute function generate_notifications_from_domain_event();
