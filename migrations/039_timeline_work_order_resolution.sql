-- =========================================================
-- 039_timeline_work_order_resolution.sql — Marine Cloud Phase 3
-- =========================================================
-- Agrega work_order_id a domain_events, resuelto automáticamente por
-- un trigger (sin tocar log_domain_event() ni ninguno de sus ~15
-- call sites, varios de los cuales están congelados de Phase 1/2).
-- =========================================================

alter table domain_events add column work_order_id uuid;
create index idx_domain_events_work_order on domain_events(work_order_id, occurred_at desc) where work_order_id is not null;

create or replace function resolve_domain_event_work_order_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.entity_type = 'work_order' then
    new.work_order_id := new.entity_id;
  elsif new.entity_type = 'appointment' then
    select work_order_id into new.work_order_id from appointments where id = new.entity_id;
  elsif new.entity_type = 'media_asset' then
    select work_order_id into new.work_order_id from media_assets where id = new.entity_id;
  elsif new.entity_type = 'work_note' then
    select work_order_id into new.work_order_id from work_notes where id = new.entity_id;
  elsif new.entity_type = 'measurement' then
    select work_order_id into new.work_order_id from measurements where id = new.entity_id;
  elsif new.entity_type = 'checklist_response' then
    select work_order_id into new.work_order_id from checklist_responses where id = new.entity_id;
  elsif new.entity_type = 'progress_update' then
    select work_order_id into new.work_order_id from progress_updates where id = new.entity_id;
  elsif new.entity_type = 'time_entry' then
    select work_order_id into new.work_order_id from time_entries where id = new.entity_id;
  end if;
  return new;
end;
$$;

create trigger trg_resolve_domain_event_wo
  before insert on domain_events
  for each row execute function resolve_domain_event_work_order_id();

revoke execute on function resolve_domain_event_work_order_id() from public, anon, authenticated;

alter table work_orders add column last_activity_at timestamptz;

create or replace function trg_update_work_order_last_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.work_order_id is not null then
    update work_orders set last_activity_at = new.occurred_at where id = new.work_order_id;
  end if;
  return new;
end;
$$;

create trigger trg_domain_events_update_last_activity
  after insert on domain_events
  for each row execute function trg_update_work_order_last_activity();

revoke execute on function trg_update_work_order_last_activity() from public, anon, authenticated;
