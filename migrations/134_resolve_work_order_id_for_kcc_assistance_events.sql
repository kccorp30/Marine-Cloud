-- =========================================================
-- 134_resolve_work_order_id_for_kcc_assistance_events.sql — Phase 9 final fix
-- =========================================================
-- BUG REAL: resolve_domain_event_work_order_id() (migración 039, NO
-- tocada retroactivamente) nunca contempló entity_type=
-- 'kcc_assistance_request' — los 5 eventos KCC_ASSISTANCE_* quedaban
-- con work_order_id NULL, rompiendo el timeline y {{vessel_name}} en
-- las notificaciones. Verificado con datos reales: los 5 eventos
-- ahora resuelven work_order_id correctamente, aparecen en el
-- timeline vía la query existente (sin tocar timeline.ts), el
-- customer no los ve (RLS de domain_events ya existente), staff sí.
-- =========================================================

create or replace function resolve_domain_event_work_order_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if new.entity_type = 'work_order' then
    select id into new.work_order_id from work_orders where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'appointment' then
    select work_order_id into new.work_order_id from appointments where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'media_asset' then
    select work_order_id into new.work_order_id from media_assets where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'work_note' then
    select work_order_id into new.work_order_id from work_notes where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'measurement' then
    select work_order_id into new.work_order_id from measurements where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'checklist_response' then
    select work_order_id into new.work_order_id from checklist_responses where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'progress_update' then
    select work_order_id into new.work_order_id from progress_updates where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'time_entry' then
    select work_order_id into new.work_order_id from time_entries where id = new.entity_id and organization_id = new.organization_id;
  elsif new.entity_type = 'kcc_assistance_request' then
    select work_order_id into new.work_order_id from kcc_assistance_requests where id = new.entity_id and organization_id = new.organization_id;
  end if;
  return new;
end;
$function$;
