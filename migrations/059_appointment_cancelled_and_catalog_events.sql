-- =========================================================
-- 059_appointment_cancelled_and_catalog_events.sql — Marine Cloud Phase 5
-- =========================================================
-- APPOINTMENT_CREATED/RESCHEDULED y TECHNICIAN_ASSIGNED/UNASSIGNED ya
-- existían desde Phase 1/2 — no se duplican. Solo se agrega lo que
-- faltaba: APPOINTMENT_CANCELLED y SERVICE_CATALOG_ITEM_CREATED/UPDATED.
-- =========================================================

create or replace function trg_emit_appointment_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    perform log_domain_event(new.organization_id, 'APPOINTMENT_CREATED', 'appointment', new.id,
      jsonb_build_object('work_order_id', new.work_order_id, 'scheduled_start', new.scheduled_start));
  elsif TG_OP = 'UPDATE' and new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    perform log_domain_event(new.organization_id, 'APPOINTMENT_CANCELLED', 'appointment', new.id,
      jsonb_build_object('work_order_id', new.work_order_id));
  elsif TG_OP = 'UPDATE' and (old.scheduled_start is distinct from new.scheduled_start) then
    perform log_domain_event(new.organization_id, 'APPOINTMENT_RESCHEDULED', 'appointment', new.id,
      jsonb_build_object('work_order_id', new.work_order_id, 'old_start', old.scheduled_start, 'new_start', new.scheduled_start));
  end if;
  return new;
end;
$$;

create or replace function trg_emit_service_catalog_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    perform log_domain_event(new.organization_id, 'SERVICE_CATALOG_ITEM_CREATED', 'service_catalog', new.id,
      jsonb_build_object('name', new.name));
  elsif TG_OP = 'UPDATE' then
    perform log_domain_event(new.organization_id, 'SERVICE_CATALOG_ITEM_UPDATED', 'service_catalog', new.id,
      jsonb_build_object('name', new.name, 'active', new.active));
  end if;
  return new;
end;
$$;

create trigger trg_service_catalog_domain_event
  after insert or update on service_catalog
  for each row execute function trg_emit_service_catalog_event();

revoke execute on function trg_emit_appointment_event() from public, anon, authenticated;
revoke execute on function trg_emit_service_catalog_event() from public, anon, authenticated;
